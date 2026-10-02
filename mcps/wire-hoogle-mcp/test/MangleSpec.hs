{-# LANGUAGE OverloadedStrings #-}

module MangleSpec (spec) where

import Data.Text (Text)
import Test.Hspec (Spec, describe, it, shouldBe)
import Wire.Hoogle.Mangle (deriveSourceLink, mangleLink)

origin :: Text
origin = "https://hoogle.zinfra.io"

spec :: Spec
spec = do
  describe "mangleLink" $ do
    it "rewrites nix-store file:// URLs to the instance" $
      mangleLink origin (Just "file:///nix/store/abc-wire-api-0.1.0-doc/share/doc/wire-api-0.1.0/html/Wire-API.html#t:Conversation")
        `shouldBe` Just "https://hoogle.zinfra.io/file/nix/store/abc-wire-api-0.1.0-doc/share/doc/wire-api-0.1.0/html/Wire-API.html#t:Conversation"
    it "passes https URLs through untouched" $
      mangleLink origin (Just "https://hackage.haskell.org/package/base/docs/Prelude.html#v:map")
        `shouldBe` Just "https://hackage.haskell.org/package/base/docs/Prelude.html#v:map"
    it "passes file:// URLs without a leading slash through unchanged" $
      mangleLink origin (Just "file://nix/store/abc")
        `shouldBe` Just "file://nix/store/abc"
    it "passes Nothing through" $
      mangleLink origin Nothing `shouldBe` Nothing
  describe "deriveSourceLink" $ do
    it "derives the source page for a mangled file link" $
      deriveSourceLink "https://hoogle.zinfra.io/file/nix/store/c50y3b9fgl3211kq8xa7yrpw68hfcdpg-aeson-2.2.4.1-doc/share/doc/aeson-2.2.4.1/html/Data-Aeson-KeyMap.html#v:map"
        `shouldBe` Just "https://hoogle.zinfra.io/file/nix/store/c50y3b9fgl3211kq8xa7yrpw68hfcdpg-aeson-2.2.4.1-doc/share/doc/aeson-2.2.4.1/html/src/Data.Aeson.KeyMap.html#map"
    it "derives the source page for a hackage link" $
      deriveSourceLink "https://hackage.haskell.org/package/base/docs/Prelude.html#v:map"
        `shouldBe` Just "https://hackage.haskell.org/package/base/docs/src/Prelude.html#map"
    it "strips the #t: anchor prefix" $
      deriveSourceLink "https://hoogle.zinfra.io/file/nix/store/abc-wire-api-0.1.0-doc/share/doc/wire-api-0.1.0/html/Wire-API.html#t:Conversation"
        `shouldBe` Just "https://hoogle.zinfra.io/file/nix/store/abc-wire-api-0.1.0-doc/share/doc/wire-api-0.1.0/html/src/Wire.API.html#Conversation"
    it "returns Nothing for non-module pages" $
      deriveSourceLink "https://hoogle.zinfra.io/file/nix/store/x-doc/share/doc/x/html/index.html"
        `shouldBe` Nothing
    it "returns Nothing for links without a page" $
      deriveSourceLink "https://hoogle.zinfra.io/file/nix/store/x-doc/share/doc/x/html/"
        `shouldBe` Nothing