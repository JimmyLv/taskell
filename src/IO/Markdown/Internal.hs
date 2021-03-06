{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module IO.Markdown.Internal where

import ClassyPrelude

import Data.Sequence (adjust')
import Data.Text as T (strip, dropAround)
import Data.Text.Encoding (decodeUtf8With)

import Data.Taskell.Date (dayToOutput)
import Data.Taskell.Lists (Lists, newList, appendToLast)
import Data.Taskell.List (List, title, tasks, updateFn, count)
import Data.Taskell.Task (Task, SubTask, new, description, subTasks, addSubTask, setSummary, setDue, subTask, name, complete, due, summary)

import IO.Config (Config, MarkdownConfig, markdown, titleOutput, taskOutput, summaryOutput, dueOutput, subtaskOutput)

-- parse code
trim :: Int -> Text -> Text
trim i = strip . drop i

trimTilde :: Text -> Text
trimTilde = strip . T.dropAround (== '~')

addSubItem :: Text -> Lists -> Lists
addSubItem t ls = adjust' updateList i ls
    where i = length ls - 1
          st | "[ ] " `isPrefixOf` t = subTask (trim 4 t) False
             | "[x] " `isPrefixOf` t = subTask (trim 4 t) True
             | "~" `isPrefixOf` t = subTask (trimTilde t) True
             | otherwise = subTask t False
          updateList l = updateFn j (addSubTask st) l
            where j = count l - 1

addSummary :: Text -> Lists -> Lists
addSummary t ls = adjust' updateList i ls
    where i = length ls - 1
          updateList l = updateFn j (setSummary t) l
            where j = count l - 1

addDue :: Text -> Lists -> Lists
addDue t ls = adjust' updateList i ls
    where i = length ls - 1
          updateList l = updateFn j (setDue t) l
            where j = count l - 1

prefix :: MarkdownConfig -> Text -> (MarkdownConfig -> Text) -> (Text -> Lists -> Lists) -> Maybe (Lists -> Lists)
prefix config str get set
    | pre `isPrefixOf` str = Just $ set (trim (length pre) str)
    | otherwise = Nothing
    where pre = get config `snoc` ' '

matches :: [(MarkdownConfig -> Text, Text -> Lists -> Lists)]
matches = [
        (titleOutput, newList)
      , (taskOutput, appendToLast . new)
      , (summaryOutput, addSummary)
      , (dueOutput, addDue)
      , (subtaskOutput, addSubItem)
    ]

start :: MarkdownConfig -> (Lists, [Int]) -> (Text, Int) -> (Lists, [Int])
start config (current, errs) (text, line) =
    case find isJust $ uncurry (prefix config text) <$> matches of
        Just (Just set) -> (set current, errs)
        _ -> if not (null (strip text))
            then (current, errs ++ [line])
            else (current, errs)


decodeError :: String -> Maybe Word8 -> Maybe Char
decodeError _ _ = Just '\65533'

parse :: Config -> ByteString -> Either Text Lists
parse config s = do
    let lns = lines $ decodeUtf8With decodeError s
    let fn = start (markdown config)
    let acc = (empty, [])
    let (lists, errs) = foldl' fn acc $ zip lns [1..]

    if null errs
        then Right lists
        else Left $ "could not parse line(s) " ++ intercalate ", " (tshow <$> errs)


-- stringify code
subTaskStringify :: MarkdownConfig -> Text -> SubTask -> Text
subTaskStringify config t st = foldl' (++) t [
        subtaskOutput config,
        " ",
        pre,
        " ",
        name st,
        "\n"
    ]
    where pre = if complete st then "[x]" else "[ ]"

summaryStringify :: MarkdownConfig -> Text -> Text
summaryStringify config sm = concat [summaryOutput config, " ", sm, "\n"]

dueStringify :: MarkdownConfig -> Day -> Text
dueStringify config day = concat [dueOutput config, " ", dayToOutput day, "\n"]

descriptionStringify :: MarkdownConfig -> Text -> Text
descriptionStringify config desc = concat [taskOutput config, " ", desc, "\n"]

taskStringify :: MarkdownConfig -> Text -> Task -> Text
taskStringify config s t = foldl' (++) s [
        descriptionStringify config (description t),
        maybe "" (dueStringify config) (due t),
        maybe "" (summaryStringify config) (summary t),
        foldl' (subTaskStringify config) "" (subTasks t)
    ]

listStringify :: MarkdownConfig -> Text -> List -> Text
listStringify config s l = foldl' (++) s [
        if null s then "" else "\n"
      , titleOutput config
      , " "
      , title l
      , "\n\n"
      , foldl' (taskStringify config) "" (tasks l)
    ]

stringify :: Config -> Lists -> ByteString
stringify config ls = encodeUtf8 $ foldl' (listStringify (markdown config)) "" ls
