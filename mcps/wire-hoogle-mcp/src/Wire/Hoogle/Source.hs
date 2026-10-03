{-# LANGUAGE OverloadedStrings #-}

-- | Resolution of the haddock "Source" link for a hoogle result.
--
-- URL munging (see git history) cannot find the real definition of
-- re-exported names: e.g. base's 'Control.Monad.forever' is defined in
-- 'GHC.Internal.Control.Monad' (ghc-internal), so a munged
-- @src\/Control.Monad.html#forever@ link is dead. Instead we fetch the docs
-- page (cached per page URL) and extract the @Source@ href that Haddock
-- renders next to the item's anchor.
module Wire.Hoogle.Source
  ( SourceCache
  , newSourceCache
  , resolveSourceLinks
  , resolveSourceLinksWith
  , pageHrefsWith
  , extractSourceLinks
  , resolveHref
  ) where

import Control.Exception (try)
import Data.Cache.LRU.IO (AtomicLRU, insert, lookup, newAtomicLRU)
import qualified Data.ByteString.Lazy as BL
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.Encoding.Error as T
import Network.HTTP.Client (HttpException, Manager, httpLbs, parseRequest, responseBody, responseStatus)
import Network.HTTP.Types (statusCode)
import Network.URI (URI(..), parseURIReference, relativeTo)
import Prelude hiding (lookup)
import Text.HTML.TagSoup (Tag(..), parseTags)
import Wire.Hoogle.Types (CachedEntry(..), uriToText)

type SourceCache = AtomicLRU Text (Map Text Text)

newSourceCache :: Int -> IO SourceCache
newSourceCache capacity = newAtomicLRU (Just (fromIntegral capacity))

-- | Resolve the haddock "Source" link for each cached entry by fetching its
-- docs page (once per page, cached) and extracting the href Haddock renders
-- next to the item's anchor.
resolveSourceLinks :: Manager -> SourceCache -> [CachedEntry] -> IO [CachedEntry]
resolveSourceLinks mgr cache = resolveSourceLinksWith (pageHrefs mgr cache)

-- | @resolveSourceLinks@ with the docs-page fetch abstracted out, so tests can
-- stub it.
resolveSourceLinksWith :: (URI -> IO (Map Text Text)) -> [CachedEntry] -> IO [CachedEntry]
resolveSourceLinksWith pageFetch = mapM (resolveEntry pageFetch)

resolveEntry :: (URI -> IO (Map Text Text)) -> CachedEntry -> IO CachedEntry
resolveEntry pageFetch entry =
  case ceLink entry of
    Nothing -> pure entry
    Just link ->
      let page = link { uriFragment = "" }
          frag = dropHash (uriFragment link)
      in if null frag
        then pure entry
        else do
          hrefs <- pageFetch page
          let source = do
                href <- Map.lookup (T.pack frag) hrefs
                ref <- parseURIReference (T.unpack href)
                pure (resolveHref page ref)
          pure entry { ceSourceLink = source }
  where
    -- | network-uri's @uriFragment@ includes the leading '#', but haddock
    -- anchors are stored without it.
    dropHash ('#' : rest) = rest
    dropHash s = s

-- | Fetch a docs page's anchor -> source-href map, caching per page URL.
pageHrefs :: Manager -> SourceCache -> URI -> IO (Map Text Text)
pageHrefs mgr cache = pageHrefsWith cache (fetchPage mgr)

-- | @pageHrefs@ with the page fetch abstracted out, so tests can stub it.
pageHrefsWith :: SourceCache -> (URI -> IO (Map Text Text)) -> URI -> IO (Map Text Text)
pageHrefsWith cache fetchPage page = do
  hit <- lookup (uriToText page) cache
  case hit of
    Just m -> pure m
    Nothing -> do
      m <- fetchPage page
      -- Do not cache empty results (fetch failure, 404, or a page with no
      -- def anchors): they are the result of a transient error and should be
      -- retried on the next query, not pinned for the session.
      if Map.null m
        then pure m
        else insert (uriToText page) m cache >> pure m

fetchPage :: Manager -> URI -> IO (Map Text Text)
fetchPage mgr url =
  case parseRequest (T.unpack (uriToText url)) of
    Left _ -> pure Map.empty
    Right req -> do
      resp <- try (httpLbs req mgr)
      pure $ case resp of
        Left (_ :: HttpException) -> Map.empty
        Right r
          | statusCode (responseStatus r) /= 200 -> Map.empty
          | otherwise -> extractSourceLinks (decodeUtf8 (responseBody r))
  where
    decodeUtf8 = T.decodeUtf8With T.lenientDecode . BL.toStrict

-- | Map Haddock definition anchors (e.g. @v:forever@, @t:Map@) to the raw
-- @Source@ href Haddock renders next to them (relative, resolved later).
--
-- A def anchor and its Source link always share one container block: a def
-- lives in @\<p class="src"\>@, a constructor in a @\<td class="src"\>@ table
-- cell (which never has its own Source link). Any @class="link"@ href seen
-- inside a later block (e.g. instance methods) must not be attributed to a
-- def from an earlier block, so @cur@ is reset on a new def anchor and cleared
-- at each block boundary.
extractSourceLinks :: Text -> Map Text Text
extractSourceLinks html = go (parseTags (T.unpack html)) Nothing Map.empty
  where
    go :: [Tag String] -> Maybe Text -> Map Text Text -> Map Text Text
    go [] _ acc = acc
    go (TagOpen "a" attrs : rest) cur acc =
      let am = Map.fromList attrs
          idAttr = Map.lookup "id" am
          href = Map.lookup "href" am
          cls = Map.lookup "class" am
      in case (cur, idAttr) of
           (_, Just i)
             | isDefAnchor i -> go rest (Just (T.pack i)) acc
           (Just i, _)
             | Just h <- href
             , cls == Just "link" -> go rest Nothing (Map.insert i (T.pack h) acc)
           _ -> go rest cur acc
    go (TagClose "p" : rest) cur acc = go rest Nothing acc
    go (TagClose "td" : rest) cur acc = go rest Nothing acc
    go (TagClose "table" : rest) cur acc = go rest Nothing acc
    go (_ : rest) cur acc = go rest cur acc
    isDefAnchor i = ("v:" `isPrefixOf` i) || ("t:" `isPrefixOf` i)
      where
        isPrefixOf p s = take (length p) s == p

-- | Resolve a (possibly relative) @Source@ href against the docs page URL.
resolveHref :: URI -> URI -> URI
resolveHref page ref = relativeTo ref page