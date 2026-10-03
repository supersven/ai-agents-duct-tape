{-# LANGUAGE OverloadedStrings #-}

module QuerySpec (spec) where

import Test.Hspec (Spec, describe, it, shouldBe)
import Wire.Hoogle.Query (buildSearchUrl, toEntry)
import Wire.Hoogle.Types (CachedEntry(..), HoogleResult(..), HoogleUrl(..))

spec :: Spec
spec = do
  describe "buildSearchUrl" $ do
    it "url-encodes the query and appends count" $
      buildSearchUrl "https://hoogle.zinfra.io" "a -> b" 10
        `shouldBe` "https://hoogle.zinfra.io?mode=json&format=text&hoogle=a%20-%3E%20b&count=10"
  describe "toEntry" $ do
    it "keeps full docs and mangles file:// links" $ do
      let result = HoogleResult
            { hrItem = "map :: (a -> b) -> [a] -> [b]"
            , hrDocs = "long docs that stay"
            , hrUrl = Just "file:///nix/store/abc-wire-api-0.1.0-doc/foo.html"
            , hrPackage = HoogleUrl (Just "base") Nothing
            , hrModule = HoogleUrl (Just "Prelude") Nothing
            , hrType = ""
            }
          entry = toEntry "https://hoogle.zinfra.io" result
      ceItem entry `shouldBe` "map :: (a -> b) -> [a] -> [b]"
      ceDocs entry `shouldBe` "long docs that stay"
      ceLink entry `shouldBe` Just "https://hoogle.zinfra.io/file/nix/store/abc-wire-api-0.1.0-doc/foo.html"
      ceType entry `shouldBe` ""