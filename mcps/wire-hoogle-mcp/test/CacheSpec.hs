module CacheSpec (spec) where

import Data.Cache.LRU.IO (AtomicLRU, insert, lookup, newAtomicLRU, toList)
import qualified Data.Map.Strict as Map
import Prelude hiding (lookup)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "AtomicLRU (lrucache)" $ do
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