{-# LANGUAGE OverloadedStrings #-}

module Wire.Hoogle.Cache
  ( HoogleCache
  , newHoogleCache
  , cacheKey
  , cachedQuery
  ) where

import Data.Cache.LRU.IO (AtomicLRU, insert, lookup, newAtomicLRU)
import Data.Text (Text)
import qualified Data.Text as T
import Network.HTTP.Client (Manager)
import Prelude hiding (lookup)
import Wire.Hoogle.Query (QueryError, QueryParams(..), Server(..), runQuery)
import Wire.Hoogle.Types (Config, HoogleEntry, truncateEntry)

type HoogleCache = AtomicLRU Text [HoogleEntry]

newHoogleCache :: Int -> IO HoogleCache
newHoogleCache capacity = newAtomicLRU (Just (fromIntegral capacity))

cacheKey :: Server -> QueryParams -> Text
cacheKey server qp =
  serverName <> "\0" <> qpQuery qp <> "\0" <> T.pack (show (qpCount qp))
  where
    serverName = case server of
      WireServer -> "wire"
      GeneralServer -> "general"

cachedQuery :: Manager -> HoogleCache -> Config -> Server -> QueryParams -> IO (Either QueryError [HoogleEntry])
cachedQuery mgr cache cfg server qp = do
  hit <- lookup key cache
  case hit of
    Just entries -> pure (Right (serve entries))
    Nothing -> do
      result <- runQuery mgr cfg server qp
      case result of
        Right full -> insert key full cache >> pure (Right (serve full))
        Left err -> pure (Left err)
  where
    key = cacheKey server qp
    serve = map (truncateEntry (qpFullDocs qp))