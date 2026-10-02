module Main (main) where

import Test.Hspec (hspec)

import qualified MangleSpec
import qualified TypesSpec

main :: IO ()
main = hspec $ do
  MangleSpec.spec
  TypesSpec.spec