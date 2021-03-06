{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module IO.Trello (
    TrelloToken
  , TrelloBoardID
  , getCards
) where

import ClassyPrelude

import Network.HTTP.Simple (parseRequest, httpBS, getResponseBody, getResponseStatusCode)
import Data.Aeson

import IO.Trello.List (List, trelloListToList, setCards, cards)
import IO.Trello.Card (Card, idChecklists, setChecklists)
import IO.Trello.ChecklistItem (ChecklistItem, checkItems)
import Data.Taskell.Lists (Lists)
import Data.Time.LocalTime (TimeZone, getCurrentTimeZone)

type ReaderTrelloToken a = ReaderT TrelloToken IO a

type TrelloToken = Text
type TrelloBoardID = Text
type TrelloChecklistID = Text

key :: Text
key = "80dbcf6f88f62cc5639774e13342c20b"

root :: Text
root = "https://api.trello.com/1/"

fullURL :: Text -> ReaderTrelloToken String
fullURL uri = do
    token <- ask
    return . unpack $ concat [root, uri, "&key=", key, "&token=", token]

boardURL :: TrelloBoardID -> ReaderTrelloToken String
boardURL board = fullURL $ concat [
        "boards/", board, "/lists",
        "?cards=open",
        "&card_fields=name,due,desc,idChecklists",
        "&fields=id,name,cards"
    ]

checklistURL :: TrelloChecklistID -> ReaderTrelloToken String
checklistURL checklist = fullURL $ concat [
        "checklists/", checklist,
        "?fields=id",
        "&checkItem_fields=name,state"
    ]

trelloListsToLists :: TimeZone -> [List] -> Lists
trelloListsToLists tz ls = fromList $ trelloListToList tz <$> ls

fetch :: String -> IO (Int, ByteString)
fetch url = do
    request <- parseRequest url
    response <- httpBS request
    return (getResponseStatusCode response, getResponseBody response)

getChecklist :: TrelloChecklistID -> ReaderTrelloToken (Either Text [ChecklistItem])
getChecklist checklist = do
    url <- checklistURL checklist
    (status, body) <- lift $ fetch url

    return $ case status of
        200 -> case checkItems <$> decodeStrict body of
            Just ls -> Right ls
            Nothing -> Left "Could not parse response. Please file an Issue on GitHub."
        429 -> Left "Too many checklists"
        _ -> Left $ tshow status ++ " error while fetching checklist " ++ checklist

updateCard :: Card -> ReaderTrelloToken (Either Text Card)
updateCard card = (setChecklists card . concat <$>) . sequence <$> checklists
    where checklists = sequence $ getChecklist <$> idChecklists card

updateList :: List -> ReaderTrelloToken (Either Text List)
updateList l = (setCards l <$>) . sequence <$> sequence (updateCard <$> cards l)

getChecklists :: [List] -> ReaderTrelloToken (Either Text [List])
getChecklists ls = sequence <$> sequence (updateList <$> ls)

getCards :: TrelloBoardID -> ReaderTrelloToken (Either Text Lists)
getCards board = do
    url <- boardURL board
    (status, body) <- lift $ fetch url
    timezone <- lift getCurrentTimeZone

    putStrLn "Fetching from Trello..."

    case status of
        200 -> case decodeStrict body of
            Just raw -> fmap (trelloListsToLists timezone) <$> getChecklists raw
            Nothing -> return $ Left "Could not parse response. Please file an Issue on GitHub."
        404 -> return . Left $ "Could not find Trello board " ++ board ++ ". Make sure the ID is correct"
        401 -> return . Left $ "You do not have permission to view Trello board " ++ board
        _ -> return . Left $ tshow status ++ " error. Cannot fetch from Trello."
