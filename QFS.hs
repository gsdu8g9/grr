-- (c) copyright 2012 cqx limited - distribution limited

{-# LANGUAGE ScopedTypeVariables, DatatypeContexts #-}

module QFS where
  import Data.List
  import Control.Monad.Trans

  -- QFS = Query/Feedback/Storage - lack better name for now...

  -- I think I want to end up with a monad transformer where there
  -- is a read query operation where that read query must be of a type
  -- that has Eq and an operation to inject new results discovered
  -- later/earlier, and some way of launching a new actual concrete query,
  -- distinct from reading out the results of the query,
  -- and perhaps there is a higher level composite operation consisting of
  -- launching a query and reading its results.

  -- under this, perhaps i need a distinct structure (in some state monad?)
  -- that tracks queries, records results, and calls assinged callbacks.

  -- I think this can be built and tested separately, and the
  -- monad (transformer) can be put on top of that, perhaps?

  -- what environment does this QFS structure need to exist in? I think it
  -- necessarily needs to sit in a monad, so that it can make callbacks
  -- (does that need to be a monad?)

  -- do I need the idea of a "primary query" execution which will launch
  -- the query, which may happen both before and after "secondary results"
  -- have been received? In the DNS case, I can receive additional RR data
  -- before I've actually performed a query (and indeed, I might not even
  -- be able to perform that query with out the additional data)

  -- perhaps I need to provide an initial callback for "making the offical
  -- query", at construction time?

  -- | This is immutable. There will be operations which take a QFSState and
  --   yield a new QFSState; those operations will also have to invoke the
  --   callbacks as necessary, I think.

  data (Eq qType, Eq resType, Monad m) => QFSState qType resType m = QFSState [(qType, [resType], [resType -> m()])]

  -- | Describes the state of a QFS store at any particular instant in time.

  statsForQFS :: (Show resType, Show qType, Eq resType,  Eq qType, Monad m) => QFSState qType resType m -> String
  statsForQFS (QFSState l) = "QFS: "++(show (map (\(q, rl, cb) -> show (q, rl, length cb)) l))


  emptyQFS :: (Eq resType, Eq qType, Monad m) => QFSState qType resType m
  emptyQFS = QFSState []

  -- | Pushes a result for a particular query into the structure, whether
  --   that query has been "launched" or not (whatever that means).
  --   It will need to invoke any registered callbacks for this query.

  pushResult :: (Eq resType, Eq qType, Monad m) => QFSState qType resType m -> (qType, resType) -> m (QFSState qType resType m)
  pushResult i@(QFSState entries) (q,r) = do
    let (onlyQ, allExceptQ) = partition (\(qe,_,_) -> qe == q) entries
    let resultsList = concat $ map (\(_,a,_)->a) onlyQ
    let callbacksList = concat $ map (\(_,_,a)->a) onlyQ
    let res = if r `elem` resultsList then i else QFSState (allExceptQ ++ [(q, resultsList ++ [r], callbacksList)])
    mapM_ (\callback -> callback r) callbacksList
    return res

  -- | pushes a callback to be invoked when a particular query result
  --   is pushed, and if there are any existing results for that query, then
  --   invokes the callback immediately for each of them.
  pushCallback :: (Eq resType, Eq qType, Monad m) => QFSState qType resType m -> qType -> (resType -> m()) -> m (QFSState qType resType m)
  pushCallback i@(QFSState entries) q callback = do
    let (onlyQ, allExceptQ) = partition (\(qe,_,_) -> qe == q) entries
    let resultsList = concat $ map (\(_,a,_)->a) onlyQ
    let callbacksList = concat $ map (\(_,_,a)->a) onlyQ
    let res = QFSState (allExceptQ ++ [(q, resultsList, callbacksList ++ [callback])])
    mapM_ callback resultsList -- callback on existing results.
    return res

  -- ok, what should this monad look like? (if it is even a monad...)
  -- its "sequence/state-like"
  -- we can at least lift an operation into the monad from the
  --    underlying monad.

  data Monad m => QFST m a = QFST { runQFST :: m a }

  instance Monad m => Monad (QFST m) where
    return a = QFST (return a)
    (l :: QFST m t) >>= (k :: t -> QFST m v) =
      QFST $ do -- in the inner monad
                a <- runQFST l
                b <- runQFST (k a)
                return b

  -- QFS stateful transformer around monad m
{-
  instance Monad m => Monad (QFST m) where
    ((QLift op) :: QFST m a) >>= (f :: a -> QFST m b) = op >>= f
    return a = QLift (return a)

  instance MonadTrans QFST where
    lift op = QLift op
-}

