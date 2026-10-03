module Main (main) where

import Test.Hspec (hspec)

import qualified CacheSpec
import qualified MangleSpec
import qualified QuerySpec
import qualified SourceSpec
import qualified TypesSpec

main :: IO ()
main = hspec $ do
  MangleSpec.spec
  SourceSpec.spec
  TypesSpec.spec
  QuerySpec.spec
  CacheSpec.spec