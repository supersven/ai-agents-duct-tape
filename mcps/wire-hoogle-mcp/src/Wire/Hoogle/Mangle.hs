{-# LANGUAGE OverloadedStrings #-}

module Wire.Hoogle.Mangle (mangleLink, deriveSourceLink) where

import Control.Monad (guard)
import Data.Char (isUpper)
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

-- | Derive the haddock source-page URL from a docs link: insert @src/@ before
-- the page (hyphens back to dots) and drop the @v:@/@t:@ anchor prefix, e.g.
-- @...\/html\/Data-Aeson-KeyMap.html#v:map@ -> @...\/html\/src\/Data.Aeson.KeyMap.html#map@.
-- Nothing for non-module pages (index, doc-index, ...) or when the link has no
-- page path.
deriveSourceLink :: Text -> Maybe Text
deriveSourceLink url = do
  let (path, frag) = T.breakOn "#" url
      (dir, page) = T.breakOnEnd "/" path
  base <- T.stripSuffix ".html" page
  guard (isModuleName base)
  pure (dir <> "src/" <> T.replace "-" "." base <> ".html" <> sourceFrag frag)
  where
    isModuleName name = case T.uncons name of
      Just (c, _) -> isUpper c
      Nothing -> False
    sourceFrag f
      | "#v:" `T.isPrefixOf` f = "#" <> T.drop 3 f
      | "#t:" `T.isPrefixOf` f = "#" <> T.drop 3 f
      | otherwise = f