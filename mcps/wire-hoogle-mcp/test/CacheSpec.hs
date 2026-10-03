{-# LANGUAGE OverloadedStrings #-}

module CacheSpec (spec) where

import Data.Cache.LRU.IO (AtomicLRU, insert, lookup, newAtomicLRU, toList)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Maybe (fromJust)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Network.URI (URI, parseURI)
import Prelude hiding (lookup)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldNotBe)
import Wire.Hoogle.Cache (cacheKey, cachedQueryWith, newHoogleCache)
import Wire.Hoogle.Query (QueryError(..), QueryParams(..), Server(..))
import Wire.Hoogle.Types (CachedEntry(..), Config(..), OutputEntry(..))

uri :: String -> URI
uri = fromJust . parseURI

fullEntry :: CachedEntry
fullEntry = CachedEntry (Just "base") (Just "Prelude") "map :: (a -> b) -> [a] -> [b]" (T.replicate 1000 "x") Nothing Nothing ""

cfg :: Config
cfg = Config (uri "https://hoogle.zinfra.io") (uri "https://hoogle.haskell.org") 10

spec :: Spec
spec = do
  describe "AtomicLRU (lrucache)" $ do
    it "evicts the least-recently-used entries at capacity" $ do
      cache <- newAtomicLRU (Just 2) :: IO (AtomicLRU Int Int)
      insert 1 1 cache
      insert 2 2 cache
      insert 3 3 cache
      entries <- toList cache
      Map.fromList entries `shouldBe` Map.fromList [(2, 2), (3, 3)]
    it "refreshes recency on lookup" $ do
      cache <- newAtomicLRU (Just 2) :: IO (AtomicLRU Int Int)
      insert 1 1 cache
      insert 2 2 cache
      _ <- lookup 1 cache
      insert 3 3 cache
      entries <- toList cache
      Map.fromList entries `shouldBe` Map.fromList [(1, 1), (3, 3)]
  describe "cacheKey" $ do
    it "distinguishes different servers for the same query" $
      cacheKey WireServer (QueryParams "map" 10 False)
        `shouldNotBe` cacheKey GeneralServer (QueryParams "map" 10 False)
    it "distinguishes different counts" $
      cacheKey WireServer (QueryParams "map" 10 False)
        `shouldNotBe` cacheKey WireServer (QueryParams "map" 20 False)
    it "does not distinguish fullDocs" $
      cacheKey WireServer (QueryParams "map" 10 False)
        `shouldBe` cacheKey WireServer (QueryParams "map" 10 True)
  describe "cachedQuery" $ do
    it "fetches on miss, serves truncated, and reuses the entry for a full-docs request" $ do
      cache <- newHoogleCache 10
      let truncatedQp = QueryParams "map" 10 False
          fullQp = QueryParams "map" 10 True
          stub _ _ = pure (Right [fullEntry])
      truncated <- cachedQueryWith stub cache cfg WireServer truncatedQp
      case truncated of
        Right [e] -> oeDocs e `shouldBe` T.take 500 (T.replicate 1000 "x")
        _ -> expectationFailure "expected a truncated result"
      full <- cachedQueryWith (error "must not fetch on cache hit") cache cfg WireServer fullQp
      case full of
        Right [e] -> oeDocs e `shouldBe` T.replicate 1000 "x"
        _ -> expectationFailure "expected a full-docs result"
    it "does not cache errors" $ do
      cache <- newHoogleCache 10
      calls <- newIORef 0
      let stub _ _ = modifyIORef' calls (+ 1) >> pure (Left (QueryBadStatus 500))
          qp = QueryParams "map" 10 False
      res1 <- cachedQueryWith stub cache cfg WireServer qp
      res2 <- cachedQueryWith stub cache cfg WireServer qp
      n <- readIORef calls
      case res1 of
        Left (QueryBadStatus 500) -> pure ()
        _ -> expectationFailure "expected QueryBadStatus 500"
      case res2 of
        Left (QueryBadStatus 500) -> pure ()
        _ -> expectationFailure "expected QueryBadStatus 500"
      n `shouldBe` 2