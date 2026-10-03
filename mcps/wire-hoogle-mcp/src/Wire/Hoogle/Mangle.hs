{-# LANGUAGE OverloadedStrings #-}

module Wire.Hoogle.Mangle (mangleLink) where

import Data.Text (Text)
import qualified Data.Text as T

-- | Rewrite a docs URL for the instance actually queried: nix-store file:///
-- URLs (leading slash required, as Wire emits them) are served by the instance
-- under <origin>/file/...; other URLs pass through unchanged.
mangleLink :: Text -> Maybe Text -> Maybe Text
mangleLink origin (Just url)
  | "file:///" `T.isPrefixOf` url = Just (origin <> "/file" <> T.drop 7 url)
  | otherwise = Just url
mangleLink _ Nothing = Nothing
