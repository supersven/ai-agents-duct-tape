{-# LANGUAGE OverloadedStrings #-}

module MangleSpec (spec) where

import Data.Maybe (fromJust)
import Network.URI (URI, parseURI)
import Test.Hspec (Spec, describe, it, shouldBe)
import Wire.Hoogle.Mangle (mangleLink)
import Wire.Hoogle.Types (uriToText)

uri :: String -> URI
uri = fromJust . parseURI

spec :: Spec
spec = do
  describe "mangleLink" $ do
    let origin = uri "https://hoogle.zinfra.io"
    it "rewrites nix-store file:// URLs to the instance" $
      mangleLink origin (Just (uri "file:///nix/store/abc-wire-api-0.1.0-doc/share/doc/wire-api-0.1.0/html/Wire-API.html#t:Conversation"))
        `shouldBe` Just (uri "https://hoogle.zinfra.io/file/nix/store/abc-wire-api-0.1.0-doc/share/doc/wire-api-0.1.0/html/Wire-API.html#t:Conversation")
    it "passes https URLs through untouched" $
      mangleLink origin (Just (uri "https://hackage.haskell.org/package/base/docs/Prelude.html#v:map"))
        `shouldBe` Just (uri "https://hackage.haskell.org/package/base/docs/Prelude.html#v:map")
    it "passes file:// URLs without a leading slash through unchanged" $
      mangleLink origin (Just (uri "file://nix/store/abc"))
        `shouldBe` Just (uri "file://nix/store/abc")
    it "preserves the fragment and renders canonically" $
      uriToText (fromJust (mangleLink origin (Just (uri "file:///nix/store/abc-doc/html/Foo.html#v:bar"))))
        `shouldBe` "https://hoogle.zinfra.io/file/nix/store/abc-doc/html/Foo.html#v:bar"
    it "passes Nothing through" $
      mangleLink origin Nothing `shouldBe` Nothing