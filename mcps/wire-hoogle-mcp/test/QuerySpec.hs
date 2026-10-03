{-# LANGUAGE OverloadedStrings #-}

module QuerySpec (spec) where

import Data.Maybe (fromJust)
import Network.URI (URI, parseURI)
import Test.Hspec (Spec, describe, it, shouldBe)
import Wire.Hoogle.Query (buildSearchUrl, toEntry)
import Wire.Hoogle.Types (CachedEntry(..), HoogleResult(..), HoogleUrl(..), uriToText)

uri :: String -> URI
uri = fromJust . parseURI

spec :: Spec
spec = do
  describe "buildSearchUrl" $ do
    it "url-encodes the query and appends count" $
      buildSearchUrl (uri "https://hoogle.zinfra.io") "a -> b" 10
        `shouldBe` "https://hoogle.zinfra.io?mode=json&format=text&hoogle=a%20-%3E%20b&count=10"
  describe "toEntry" $ do
    it "keeps full docs and mangles file:// links" $ do
      let result = HoogleResult
            { hrItem = "map :: (a -> b) -> [a] -> [b]"
            , hrDocs = "long docs that stay"
            , hrUrl = Just (uri "file:///nix/store/abc-wire-api-0.1.0-doc/foo.html")
            , hrPackage = HoogleUrl (Just "base") Nothing
            , hrModule = HoogleUrl (Just "Prelude") Nothing
            , hrType = ""
            }
          entry = toEntry (uri "https://hoogle.zinfra.io") result
      ceItem entry `shouldBe` "map :: (a -> b) -> [a] -> [b]"
      ceDocs entry `shouldBe` "long docs that stay"
      uriToText (fromJust (ceLink entry)) `shouldBe` "https://hoogle.zinfra.io/file/nix/store/abc-wire-api-0.1.0-doc/foo.html"
      ceType entry `shouldBe` ""