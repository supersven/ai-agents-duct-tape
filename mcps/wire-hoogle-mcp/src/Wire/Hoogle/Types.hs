{-# LANGUAGE OverloadedStrings #-}

module Wire.Hoogle.Types
  ( Config(..)
  , loadConfig
  , CachedEntry(..)
  , OutputEntry(..)
  , HoogleResult(..)
  , HoogleUrl(..)
  , dedupeBySourceLink
  , truncateDocs
  , toOutputEntry
  , uriToText
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Aeson.Types (Parser)
import Data.List (nub)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Network.URI (URI, parseURI, uriToString)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

data Config = Config
  { cfgWireUrl :: URI
  , cfgGeneralUrl :: URI
  , cfgCacheMaxEntries :: Int
  }
  deriving (Eq, Show)

defaultWireUrl :: URI
defaultWireUrl = parseURIorDie "https://hoogle.zinfra.io"

defaultGeneralUrl :: URI
defaultGeneralUrl = parseURIorDie "https://hoogle.haskell.org"

defaultCacheMaxEntries :: Int
defaultCacheMaxEntries = 5000

parseURIorDie :: String -> URI
parseURIorDie s = fromMaybe (error ("invalid default hoogle URL: " ++ s)) (parseURI s)

loadConfig :: IO Config
loadConfig = do
  wireUrl <- envOr "WIRE_HOOGLE_URL" defaultWireUrl
  generalUrl <- envOr "GENERAL_HOOGLE_URL" defaultGeneralUrl
  cacheMax <- max 1 <$> envIntOr "HOOGLE_CACHE_MAX_ENTRIES" defaultCacheMaxEntries
  pure (Config wireUrl generalUrl cacheMax)
  where
    envOr :: String -> URI -> IO URI
    envOr name def = do
      v <- lookupEnv name
      pure (maybe def (fromMaybe def . parseURI) v)
    envIntOr :: String -> Int -> IO Int
    envIntOr name def = do
      v <- lookupEnv name
      pure (maybe def (fromMaybe def . readMaybe) v)

data HoogleUrl = HoogleUrl { huName :: Maybe Text, huUrl :: Maybe URI }
  deriving (Eq, Show)

instance FromJSON HoogleUrl where
  parseJSON = withObject "HoogleUrl" $ \o -> do
    name <- o .:? "name"
    url <- o .:? "url" :: Parser (Maybe Text)
    pure (HoogleUrl name (url >>= parseURI . T.unpack))

data HoogleResult = HoogleResult
  { hrItem :: Text
  , hrDocs :: Text
  , hrUrl :: Maybe URI
  , hrPackage :: HoogleUrl
  , hrModule :: HoogleUrl
  , hrType :: Text
  }
  deriving (Eq, Show)

instance FromJSON HoogleResult where
  parseJSON = withObject "HoogleResult" $ \o -> do
    item <- o .: "item"
    docs <- o .:? "docs" .!= ""
    url <- o .:? "url" :: Parser (Maybe Text)
    package <- o .:? "package" .!= HoogleUrl Nothing Nothing
    module' <- o .:? "module" .!= HoogleUrl Nothing Nothing
    type' <- o .:? "type" .!= ""
    pure (HoogleResult item docs (url >>= parseURI . T.unpack) package module' type')

-- | What the cache stores: full, untruncated docs, mangled link, and the
-- resolved haddock "Source" link. Nothing derived per request (no truncation
-- flag); the source link needs a docs-page fetch, so it is resolved at query
-- time and cached.
data CachedEntry = CachedEntry
  { cePackage :: Maybe Text
  , ceModule :: Maybe Text
  , ceItem :: Text
  , ceDocs :: Text
  , ceLink :: Maybe URI
  , ceSourceLink :: Maybe URI
  , ceType :: Text
  , ceAlsoIn :: [Text]
  }
  deriving (Eq, Show)

-- | What is served to the agent: docs truncated to ~500 chars unless full docs
-- were requested, plus the derived source link.
data OutputEntry = OutputEntry
  { oePackage :: Maybe Text
  , oeModule :: Maybe Text
  , oeItem :: Text
  , oeDocs :: Text
  , oeDocsTruncated :: Bool
  , oeLink :: Maybe Text
  , oeSourceLink :: Maybe Text
  , oeType :: Maybe Text
  , oeAlsoIn :: [Text]
  }
  deriving (Eq, Show)

instance ToJSON OutputEntry where
  toJSON e = object
    [ "package" .= oePackage e
    , "module" .= oeModule e
    , "item" .= oeItem e
    , "docs" .= oeDocs e
    , "docs_truncated" .= oeDocsTruncated e
    , "link" .= oeLink e
    , "source_link" .= oeSourceLink e
    , "type" .= oeType e
    , "also_in" .= oeAlsoIn e
    ]

-- | Render a 'URI' to its canonical string form.
uriToText :: URI -> Text
uriToText u = T.pack (uriToString id u "")

-- | Collapse re-export duplicates: entries whose real definition (resolved
-- @source_link@) is the same. Keeps the first occurrence per source link and
-- every entry without a source link, preserving order. Each collapsed row's
-- @package\/module@ is appended to the survivor's @also_in@ (deduped, in
-- encounter order). Wire Hoogle returns the same name once per re-exporting
-- module (Prelude, Data.List, GHC.Base, ...) with identical source links; this
-- cuts that noise on every query while keeping the re-export locations.
dedupeBySourceLink :: [CachedEntry] -> [CachedEntry]
dedupeBySourceLink es = [ e { ceAlsoIn = alsoInFor (ceSourceLink e) } | e <- survivors ]
  where
    survivors = go Set.empty es
      where
        go _ [] = []
        go seen (e : rest) =
          case ceSourceLink e of
            Nothing -> e : go seen rest
            Just src
              | src `Set.member` seen -> go seen rest
              | otherwise -> e : go (Set.insert src seen) rest

    -- first entry (the survivor) per source link
    firstBySrc :: Map.Map URI CachedEntry
    firstBySrc = foldl step Map.empty es
      where
        step m e = case ceSourceLink e of
          Just src | not (Map.member src m) -> Map.insert src e m
          _ -> m

    alsoInFor :: Maybe URI -> [Text]
    alsoInFor Nothing = []
    alsoInFor (Just src) =
      case Map.lookup src firstBySrc of
        Nothing -> []
        Just survivor ->
          nub [ loc | e <- es
                    , ceSourceLink e == Just src
                    , let loc = locOf e
                    , loc /= locOf survivor
                    , not (T.null loc) ]

    locOf :: CachedEntry -> Text
    locOf e = case (cePackage e, ceModule e) of
      (Nothing, Nothing) -> ""
      (Just p, Nothing) -> p
      (Nothing, Just m) -> m
      (Just p, Just m) -> p <> "/" <> m

truncateDocs :: Int -> Text -> (Text, Bool)
truncateDocs limit docs
  | T.length docs <= limit = (docs, False)
  | otherwise = (T.take limit docs, True)

toOutputEntry :: Bool -> CachedEntry -> OutputEntry
toOutputEntry fullDocs entry = OutputEntry
  { oePackage = cePackage entry
  , oeModule = ceModule entry
  , oeItem = ceItem entry
  , oeDocs = docs
  , oeDocsTruncated = truncated
  , oeLink = uriToText <$> ceLink entry
  , oeSourceLink = uriToText <$> ceSourceLink entry
  , oeType = type'
  , oeAlsoIn = ceAlsoIn entry
  }
  where
    (docs, truncated) =
      if fullDocs then (ceDocs entry, False) else truncateDocs 500 (ceDocs entry)
    type' = if T.null (ceType entry) then Nothing else Just (ceType entry)