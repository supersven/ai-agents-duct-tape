{-# LANGUAGE OverloadedStrings #-}

module Wire.Hoogle.Cache
  ( HoogleCache
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
import Wire.Hoogle.Types (CachedEntry, Config, OutputEntry, toOutputEntry)

type HoogleCache = AtomicLRU Text [CachedEntry]

newHoogleCache :: Int -> IO HoogleCache
newHoogleCache capacity = newAtomicLRU (Just (fromIntegral capacity))

cacheKey :: Server -> QueryParams -> Text
cacheKey server qp =
  serverName <> "\0" <> qpQuery qp <> "\0" <> T.pack (show (qpCount qp))
  where
    serverName = case server of
      WireServer -> "wire"
      GeneralServer -> "general"

cachedQuery :: Manager -> HoogleCache -> Config -> Server -> QueryParams -> IO (Either QueryError [OutputEntry])
cachedQuery mgr cache cfg server qp = cachedQueryWith (runQuery mgr cfg) cache cfg server qp

-- | @cachedQuery@ with the network fetch abstracted out, so tests can stub it.
-- Caches full @CachedEntry@s; serves @OutputEntry@s (truncation + source-link
-- derivation applied per request via 'toOutputEntry').
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