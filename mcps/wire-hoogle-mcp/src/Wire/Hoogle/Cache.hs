{-# LANGUAGE OverloadedStrings #-}

module Wire.Hoogle.Cache
  ( Caches(..)
  , newCaches
  , HoogleCache
  , newHoogleCache
  , cacheKey
  , cachedQuery
  , cachedQueryWith
  ) where

import Data.Cache.LRU.IO (AtomicLRU, insert, lookup, newAtomicLRU)
import Data.Text (Text)
import qualified Data.Text as T
import Network.HTTP.Client (Manager)
import Prelude hiding (lookup)
import Wire.Hoogle.Query (QueryError, QueryParams(..), Server(..), runQuery)
import Wire.Hoogle.Source (SourceCache, newSourceCache, resolveSourceLinks)
import Wire.Hoogle.Types (CachedEntry, Config, OutputEntry, toOutputEntry)

type HoogleCache = AtomicLRU Text [CachedEntry]

newHoogleCache :: Int -> IO HoogleCache
newHoogleCache capacity = newAtomicLRU (Just (fromIntegral capacity))

-- | The two caches a session uses, composed so they are created and threaded
-- together: the query cache (query key -> entries) and the page cache (docs
-- page URL -> anchor/source-href map, used only while filling the query cache).
data Caches = Caches
  { cachesHoogle :: HoogleCache
  , cachesSource :: SourceCache
  }

newCaches :: Int -> IO Caches
newCaches capacity = Caches
  <$> newHoogleCache capacity
  <*> newSourceCache capacity

cacheKey :: Server -> QueryParams -> Text
cacheKey server qp =
  serverName <> "\0" <> qpQuery qp <> "\0" <> T.pack (show (qpCount qp))
  where
    serverName = case server of
      WireServer -> "wire"
      GeneralServer -> "general"

-- | Production @cachedQuery@: fetches, then resolves the haddock "Source" link
-- for each result (needs a docs-page fetch, so it is part of the cache fill,
-- not per request).
cachedQuery :: Manager -> Caches -> Config -> Server -> QueryParams -> IO (Either QueryError [OutputEntry])
cachedQuery mgr caches cfg server qp =
  cachedQueryWith fetch (cachesHoogle caches) cfg server qp
  where
    fetch server' qp' = do
      res <- runQuery mgr cfg server' qp'
      case res of
        Left err -> pure (Left err)
        Right entries -> Right <$> resolveSourceLinks mgr (cachesSource caches) entries

-- | @cachedQuery@ with the network fetch abstracted out, so tests can stub it.
-- Caches full @CachedEntry@s (including the resolved source link); serves
-- @OutputEntry@s (truncation applied per request via 'toOutputEntry').
cachedQueryWith
  :: (Server -> QueryParams -> IO (Either QueryError [CachedEntry]))
  -> HoogleCache
  -> Config
  -> Server
  -> QueryParams
  -> IO (Either QueryError [OutputEntry])
cachedQueryWith fetch cache cfg server qp = do
  hit <- lookup key cache
  case hit of
    Just entries -> pure (Right (serve entries))
    Nothing -> do
      result <- fetch server qp
      case result of
        Right full -> insert key full cache >> pure (Right (serve full))
        Left err -> pure (Left err)
  where
    key = cacheKey server qp
    serve = map (toOutputEntry (qpFullDocs qp))