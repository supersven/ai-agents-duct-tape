{-# LANGUAGE OverloadedStrings #-}

module MangleSpec (spec) where

import Data.Text (Text)
import Test.Hspec (Spec, describe, it, shouldBe)
import Wire.Hoogle.Mangle (mangleLink)

origin :: Text
origin = "https://hoogle.zinfra.io"

spec :: Spec
spec = describe "mangleLink" $ do
  it "rewrites nix-store file:// URLs to the instance" $
    mangleLink origin (Just "file:///nix/store/abc-wire-api-0.1.0-doc/share/doc/wire-api-0.1.0/html/Wire-API.html#t:Conversation")
      `shouldBe` Just "https://hoogle.zinfra.io/file/nix/store/abc-wire-api-0.1.0-doc/share/doc/wire-api-0.1.0/html/Wire-API.html#t:Conversation"
  it "passes https URLs through untouched" $
    mangleLink origin (Just "https://hackage.haskell.org/package/base/docs/Prelude.html#v:map")
      `shouldBe` Just "https://hackage.haskell.org/package/base/docs/Prelude.html#v:map"
  it "passes Nothing through" $
    mangleLink origin Nothing `shouldBe` Nothing