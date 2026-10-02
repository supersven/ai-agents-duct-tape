{-# LANGUAGE OverloadedStrings #-}

module QuerySpec (spec) where

import Test.Hspec (Spec, describe, it, shouldBe)
import Wire.Hoogle.Query (buildSearchUrl)

spec :: Spec
spec = describe "buildSearchUrl" $ do
  it "url-encodes the query and appends count" $
    buildSearchUrl "https://hoogle.zinfra.io" "a -> b" 10
      `shouldBe` "https://hoogle.zinfra.io?mode=json&format=text&hoogle=a%20-%3E%20b&count=10"