module Main (main) where

import Test.Hspec (hspec)

import qualified CacheSpec
import qualified MangleSpec
import qualified QuerySpec
import qualified TypesSpec

main :: IO ()
main = hspec $ do
  MangleSpec.spec
  TypesSpec.spec
  QuerySpec.spec
  CacheSpec.spec