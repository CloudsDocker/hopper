{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE DataKinds, GADTs  #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE PolyKinds #-}

#if MIN_VERSION_GLASGOW_HASKELL(8,0,0,0)
{-# LANGUAGE StrictData #-}
{-# LANGUAGE TypeInType #-}
{-# LANGUAGE DuplicateRecordFields #-}
#endif

{-# LANGUAGE ConstraintKinds   #-}
{-# LANGUAGE ScopedTypeVariables  #-}


--- all downstream clients of this module might need this plugin too?
--{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}
--
-- {-# LANGUAGE TypeInType #-}

module Hopper.Internal.Reference.HOAS(
  Exp(..)
  ,evalB -- TODO: implement this, Carter
  ,evalSingle
  ,reify
  ,reflect
  ,Sort(..)
  ,PrimType(..)
  ,DataDesc --- this will be the data * DECL data type?
  ,Relevance(..)
  ,ValueCanCase(..)
  ,Value(..)
  ,Neutral(..)
  ,Literal(..)
  --,ValFun(..)
  ,ThunkValue(..)
  --,ExpFun(..)
  ,SomeArityValFun(..)
  ,SomeArityExpFun(..)
  ,RawFunction(..)
  ,SizedList(..)
  ,sizedFmap
  ,sizedMapM
  ,PiTel(..)
  ,SigmaTel(..)
  --,ThunkValuation(..)
  --,TwoFlipF(..)
  -- these reexports are subject to change or delition
  ,MutVar
  ,Proxy(..)
  ,SomeNatF(..)
  ,SimpleValue
  --,SizedTelescope(..)
  ) where

import qualified GHC.TypeLits as GT
import Data.Primitive.MutVar as PMV
import Data.Map.Strict (Map)
import Data.Type.Equality
import qualified Data.Map.Strict as Map
--import Control.Monad.Primitive
import GHC.TypeLits (Nat,KnownNat,sameNat,natVal)
#if MIN_VERSION_GLASGOW_HASKELL(8,0,0,0)
--import GHC.Exts (Constraint, Type )
import Data.Kind (type (*))
-- TypeInType forces this latter import
-- and * = Type as a magic synonym for compat
-- and Type = TYPE LiftedPointer rep
#elif MIN_VERSION_GLASGOW_HASKELL(7,10,3,0)
--import GHC.Exts (Constraint)
#else
#error "unsupported GHC version thats less than 7.10.3"
#endif
import Data.Text (Text)
import Data.Void
import Data.Proxy
import Hopper.Internal.Type.Relevance
import Control.Monad.STE
import Numeric.Natural


{- A Higher Order  abstract syntax model of the term AST
There will be a few infelicities to simplify / leverage the use
of metalanguage (haskell) lambdas/binders

1) unboxed tuples/telescopes thereof

-}




data SomeArityValFun :: Nat -> * ->  * where
  SomeValFun :: GT.KnownNat n => Proxy n -> RawFunction n m a (Exp a) -> SomeArityValFun m a

-- for the underlying HOAS for terms, this is probably better
-- than
data RawFunction :: Nat -> Nat -> * -> (Nat ->  *) -> * where
  RawFunk :: (KnownNat domSize, KnownNat codSize ) =>
              Proxy domSize ->
              Proxy codSize ->
              (SizedList domSize domain ->  codomainF codSize) ->
              RawFunction domSize codSize domain codomainF
            -- ^ This has a nice profuntor / category / semigroupid instance!
            -- but does that matter?

{--}

data SomeArityExpFun :: Nat -> * -> * where
  -- results are always expressions
  -- which *may* become neutral upon evaluation
  SomeArityExpFun :: (GT.KnownNat n , GT.KnownNat m)=>
                     Proxy n ->
                     Proxy m  ->
                     (RawFunction n m a (Exp a)) ->
                     SomeArityExpFun m a

data Literal :: *  where --- this lives in a nother module, but leave empty for now
 LInteger :: Integer -> Literal

data DataDesc
{-
this will be used for defining new data types
-}




-- This factorization is to require
data ValueCanCase :: * -> ( * -> Nat -> * )  -> * where
  VLit :: Literal ->  ValueCanCase s neut


  --VFunction :: (SomeArityValFun resultArity (Value  s neut )) -> ValueNoThunk s neut
  VConstructor :: KnownNat m => Text {- tag -} ->
                  Proxy m ->
                  SizedList m (Value s neut)  ->
                  ValueCanCase s  neut

  --VPseudoUnboxedTuple :: [Value s neut] -> ValueNoThunk s neut
  -- unboxed tuples never exist as heap values, but may be the result of
 -- some computation

{-
TODO: add normalized types
TODO : index by "arity",
-}
{-
Neutral syntax is a parallel
-}
data Neutral :: *  -> Nat  -> * where
  NeutVariable :: Text {- this isn't quite right -} ->
                  --- ^ todo fix up this detail, Carter
                  Neutral s 1
  NeutCase :: (Neutral s 1) ->
              --( Maybe (Value?)  ) ->
              Map Text (SomeArityExpFun n (Value s Neutral )) ->
              Neutral s n
  NeutApp :: (KnownNat from, KnownNat to )=>
  -- ^ when the function is Neutral, the application is neutral
        Neutral s 1->
        Proxy from ->
        Proxy to ->
        SizedList from  (Value s Neutral) ->
        Neutral s to
  -- | Neutral Let is introduced if an argument to a function application
  -- is a nontrivial (!= NeutTrivial  or NeutValue) neutral term
  -- OR if the RHS (right hand side) of a let binding is a nontrivial neutral term
  NeutLet :: (KnownNat m, KnownNat h) =>
            Proxy m ->
            Proxy h ->
            Neutral s m ->
            (RawFunction m h (Value s Neutral) (Exp (Value s Neutral ))) ->
            Neutral s h
  NeutForce :: KnownNat to =>
        Neutral s 1 ->
        Proxy to ->
        Neutral s to
  NeutTrivial :: KnownNat to =>
        Proxy to ->
        SizedList to (Value s Neutral) ->
        Neutral s to


--- Values are either in Normal form, or Neutral, or a Thunk
---
data Value :: * -> ( * -> Nat  -> * )  -> * where
    VCanCase :: ValueCanCase s neut -> Value  s neut
    -- Normal is the wrong word
    VThunk :: KnownNat n => Proxy n -> MutVar s (ThunkValue s n neut ) -> Value s neut
    VFunk :: (RawFunction n m (Value s neut) (Exp (Value s neut))) -> Value s neut
    {- Q: Should VFUNK be  (RawFunction n m (Value s neut) (Neutral (Value s neut)))   ?
    That does suggest that Neutral needs a few more cases like multi arity expressions??? -}
    VNeutral :: neut s 1 -> Value s neut
    -- ^ only arity 1 neutral terms can embed in values


data ThunkValue:: * -> Nat -> ( * -> Nat  -> * ) -> * where
  ThunkValueResult :: SizedList n (Value s neut)  ->  ThunkValue s  n neut
  ThunkMultiNeutralResult ::  neut s n -> ThunkValue s n neut
  ThunkComputation :: (Exp  (Value s neut) n ) -> ThunkValue s n neut
  ThunkBlackHole ::  ThunkValue s n neut
  --- Q: should there be blackholes?

--data ThunkValue :: * -> ( * -> Nat -> * ) -> * where
--  ThunkValue ::KnownNat n => Proxy n -> MutVar s (ThunkValuation s n neut ) -> ThunkValue s neut
  {-  do we need this to be seperated out from VThunk? -}

--- this isn't quite right yet
{-data NeutralTerm :: * -> * where
  NeutralFreeVariable :: gvar -> NeutralTerm gvar
  StuckCase :: NeutralTerm gv -> Maybe ()
            -> [(Text, SomeExpFun )]
            -> NuetralTerm gv
    -> -}

type SimpleValue = Value Void


data Sort :: *   where
  LubSort :: [Sort ] -> Sort  -- max of a list of sorts
  SuccSort :: Sort -> Sort -- 1 up the other sorts!
  BaseSort :: Natural  -> Sort
  {- agda then has a sort OMEGA for parametrizing over universe indexes
  plus some way of having sorts take a variable  arg for concrete universe instantiation  -}

data PrimType :: * where
  PTInteger :: PrimType
 deriving(Show)

--- this is in some sense
{-
--- revisit this to think about how this may or may not help
clarify
data Telescope :: (Nat -> * ->  * -> Type) -> * -> Nat -> * where
  TZ :: f 0 t  t -> Telescope f  t 0
  TSucc :: forall t f  (n :: Nat) (m :: Nat) . (m ~ (n GT.+ 1)) =>
              (f m  t (Telescope f t n)) -> Telescope f t m-}

{- is this a profunctor? or something nuts? or both :))
   its like some sort of categorical thingy
   point being, its meant to model dependent pi
   ie
   Pi {x_1 : }
 -}
data PiTel :: Nat -> * -> *  -> * -> * where
  PiZ :: forall domainV domTy codomainTy .
       codomainTy ->
       -- ^ a Zero arg function is logically just the bare expression,
       -- merely unevaluated. that is, PiZ (Exp a) is the same as
       -- a unit value argument function  @ ()-> codomain @
       PiTel 0 domainV domTy codomainTy

  PiSucc :: forall domainV domTy codomainTy m n . (m ~ (n GT.+ 1)) =>
          domTy ->
          -- ^ * of domain / current variable
          Relevance ->
          -- ^ variable usage annotation for the thusly typed function expression
          -- usage in * level expressions is deemed cost 0
          (domainV -> PiTel n domainV domTy codomainTy ) ->
          -- ^ rest of the telescope
          PiTel m domainV domTy codomainTy

-- | @SigmaTel n sort ty val@ can be thought of as eg
  -- SigmaSigma  (Ty1 :_rel1 Sort1) (f : (val1 : Ty1 )-> Ty2 val1)
  -- yiels a pair (x : Ty1 , y : f x )
data SigmaTel :: Nat -> * -> * -> * where
  SigmaZ :: forall {-domainExp-} domainV domTy . SigmaTel 0 {-domainExp-}  domainV domTy
  -- ^ an empty sigma telescope is basically just the unit value
  SigmaSucc :: forall domainTy domainV  {-domainSort-} m n . (m ~ (n GT.+ 1)) =>
            {-domainSort ->-}
            -- ^ the type/sort of the first element
            domainTy ->
            -- ^ sigmas are pairs! so we have the "value" / "expression"
            -- of the first element, which has type domSort.
            -- Which may or may not be evaluated yet!
            Relevance ->
            -- ^ the computational relevance for the associated value
            -- usage in * level expressions is deemed cost 0
            (domainV -> SigmaTel n {-domainSort-} domainV domainTy) ->
            -- ^ second/rest of the telescope
            -- (sigmas are, after a generalized pair), and in a CBV
            -- evaluation order, Expressions should be normalized
            -- (or at least neutral , before being supplied to the dependent term )
            SigmaTel m {-domainSort-} domainV domainTy

data SomeNatF :: (Nat -> * ) -> * where
  SomeNatF ::  forall n f . GT.KnownNat n => f n -> SomeNatF f

{-
indexed descriptions are a good strawman
datatype/type model

data IDesc {l : Level}(I : Set (suc l)) : Set (suc l) where
  var : I -> IDesc I
  const : Set l -> IDesc I
  prod : IDesc I -> IDesc I -> IDesc I
  sigma : (S : Set l) -> (S -> IDesc I) -> IDesc I
  pi : (S : Set l) -> (S -> IDesc I) -> IDesc I


-}



infixr 5 :*  -- this choice 5 is adhoc and subject to change



data SizedList ::  Nat -> * -> * where
  SLNil :: SizedList 0 a
  (:*) :: a -> SizedList n a -> SizedList (n GT.+ 1) a
instance Functor (SizedList m) where
  fmap = sizedFmap

sizedFmap :: forall n a b . (a -> b) -> SizedList n a -> SizedList n b
sizedFmap _f SLNil = SLNil
sizedFmap f (a :* as) = f a :* (sizedFmap f as )

sizedMapM :: forall n a b m . Monad m  => (a -> m b) -> SizedList n a ->  m (SizedList n b)
sizedMapM _f SLNil = return SLNil
sizedMapM f (a :* as) = do tl <- (sizedMapM f as ) ; hd <- f a ; return (hd :* tl)







--data HoasType ::  * -> * ) where
--   --FunctionSpace ::


{- | the @'Exp' a @ type!
Notice that @a@ appears in both positive and negative recursively within 'Exp',
and thus is not a Functor. The idea is

[ note on Function spaces ]
the notion of unboxed tuple telescopes,
i.e. @ pi{ x_1 :r_1 t_1 .. } -> Sigma{ y_1 :g_1 h_1..}@
(where x_i and y_i are variables, r_i and g_i are relevance, and t_i and h_i are types/sorts )
in both argument and result positions (surprisingly)
results in an interesting unification of dependent sums and products
which also lends itself to some pretty cool logical embeddings!
E.g. roughly @ Void === pi {a : Type}->sigma {res : a} @ which has zero
inhabitants,
and likewise something like  @ Unit === pi{ a : Type, v : a}-> Sigma{}@
or perhaps @  Unit == pi{}->sigma{} @, as either of those types
have only one inhabitant!

-}
data Exp :: * -> Nat  -> *  where

  {-
  our function * from unboxed tuples arity n>=0 to unboxed tuples arity m >=0
  should model the following coinductive / inductive type
  forall*{x_1 :r_1 t_1 ... x_n :t_n  } -> exist*{y_1 :h_1 q_1 .. y_m :h_m q_m}

  x_i,y_i are variables of * 'a'
  r_i,h_i are values of * Relevance
  t_i,q_i are expressions 'Exp a' that evaluate to valid sorts or types

  for all j such that j<i,  x_j is in the scope of t_i,

  all x_i are in scope for every q_1 .. q_m

  for all j < i, y_j is in the scope of q_i

  -}
  --- QUESTION: is this also the right binder rep
  -- for term level lambdas?! I think so ...
  -- on the flip side, that flies in the face of a bidirectional
  -- curry style presentation of the * theory
  FunctionSpaceTypeExp :: (KnownNat piSize, KnownNat sigSize) =>
      Proxy piSize ->
      -- ^ argument arity
      Proxy sigSize ->
      -- ^ result arity

      (PiTel piSize a (Exp  a 1)
        (SigmaTel sigSize {-(Exp  a 1) -}a (Exp  a 1))) ->
      -- ^ See note on Function spaces
      -- \pi x_1 ... \pi x_piSize -> Exists y_1 ... Exists y_sigmaSize
      --
      -- TODO: figure out better note convention, Carter
      Exp  a 1
      -- ^ Functions / Types  are a single value!
      --
  DelayType :: (KnownNat sigSize) =>
      Proxy sigSize ->
      SigmaTel sigSize {-(Exp  a 1) -} a (Exp  a 1) ->
      Exp a 1
{-
TODO : ADD CASE CON AND PRIMAPP

-}
  BaseType :: PrimType -> Exp  a 1
  --ExpType :: HoasType (Exp a) -> Exp a
  --FancyAbs ::
  Sorts :: Sort  -> Exp a 1
  Abs :: (RawFunction n m a (Exp a)) -> Exp a 1
  --Abs :: SomeArityExpFun m a -> Exp  a 1
  --App :: Exp 1 a -> Exp n a -> Exp a
  App :: (KnownNat from , KnownNat to) =>
    -- We always need to check
      Proxy from ->
      Proxy to  ->
      Exp a 1 {-  from -> to, always need to chek -} ->
      -- ^ the function position, it should evaluate to a function
      -- that has input arity @from@ and result arity @to@
      -- which needs to be checked by the evaluator
      Exp a from  ->
      Exp a to
  --Pure :: a -> Exp a 1
  Return :: SizedList n (Exp a 1) -> Exp  a n
  HasType :: KnownNat n => Exp  a n-> Proxy n -> Exp  a 1 -> Exp  a n  --- aka CUT
  Delay :: KnownNat n => Proxy n -> Exp  a n -> Exp  a 1
  Force :: KnownNat n => Exp  a 1 -> Proxy n    -> Exp  a n
  -- ^ Not sure if `Force` and `Delay` should have this variable arity,
  -- But lets run with it for now
  LetExp :: Exp  a m -> (RawFunction m h a (Exp a)) -> Exp  a h
  --- ^ this is another strawman for arity of functions
  --- both LetExpExp and LetExp are essentially the same thing
  --- Let is also existential unpack for unboxed tuples, which
  -- can otherwise only be deconstructed  by calling a function
  --LetExp :: Exp  a m   -> (SizedList m a   -> Exp  a h) -> Exp   a h

  -- ^ Let IS monadic bind :)
   -- note that this doesn't quite line up the arities correctly... need to think about this more
   -- roughly Let {y_1 ..y_m} = evaluate a thing of * {}->{y_1 : t_1 .. y_m : t_m}
   --                  in  expression

  -- | 'CaseCon' is only
  CaseCon :: Exp  a 1 -- ^ the value being cased upon
        -> Maybe (Exp  a 1)  -- optional type annotation,
                          -- that should be a function from the
                          -- scrutinee to a generalization of the cases
        -> Map Text (SomeArityExpFun m a )
        -- ^ non-overlapping set of tags and continuations
        -- but all cases invoke the same continuation,
        -- and thus must have the same result arity

        -- TODO, look at sequent calc version
        -> Exp   a m


data NominalExp where

{-
queue

first order -> has feasibility sanity check
normal forms on types (values is bigger than we knew!)
BIDIRECTIONAL CHECKING (syntax) guillaume allais etc
make the Function space stuff not suck

-}


{-
-- it * checks!
>>> :t FunctionSpaceExp Proxy Proxy (PiZ (SigmaZ))
FunctionSpaceExp Proxy Proxy (PiZ (SigmaZ)) :: Exp a


>>> :t FunctionSpaceExp Proxy Proxy (PiSucc (Sorts (LubSort []) ) Omega  (\x -> PiZ (SigmaSucc (Sorts $ LubSort[]) (Var x)  Omega ((\ _y -> SigmaZ ) ) )))
FunctionSpaceExp Proxy Proxy
    (PiSucc (Sorts (LubSort []) ) Omega
    (\x -> PiZ
      (SigmaSucc (Sorts $ LubSort[]) (Var x)  Omega ((\ _y -> SigmaZ ) ) )))
  :: Exp a
-}

{-
FIXME : ARITY ZERO EVALB / CHECK THAT WE HANDLE THAT
-}

evalB :: forall s n .  KnownNat n =>
                       Exp  (Value s Neutral) n ->
                         --  STE String  s  (Neutral s {- n -}) might be more true/correct
                      STE String  s  (Neutral s n)
                      --(Either (Neutral s {- n -})  -- (SizedList n (Value s Neutral)))
evalB (App (parg :: Proxy m )
           (pres :: Proxy n)
           funExp (argExp :: (Exp (Value s Neutral ) m))) =
  do  maybFunk <- evalSingle funExp
      case maybFunk of
        (NeutTrivial (Proxy :: Proxy 1) ( v :* _)  ) -> handleFunk v

      where
    handleFunk :: (Value s Neutral) ->  STE String  s  (Neutral s n)
    handleFunk mayFunk =  case mayFunk of
        (VThunk _prox _ ) -> throwSTE "thunks shouldn't appear in argument position"
        (VCanCase _) -> throwSTE "got a literal or constructor in function position "
        (VFunk (RawFunk (pfrom :: Proxy z) (pto :: Proxy y) theFun)) ->
            do  argsM <- evalB argExp ;
                case (argsM :: Neutral s m,  sameNat parg pfrom , sameNat pto pres) of
                    (NeutTrivial _ ls , Just eq , Just req) ->
                        gcastWith req ( gcastWith eq (evalB $ theFun ls))

                    _ -> throwSTE "bad neutral arg to function" -- make neutral Let
                --case (sameNat parg pfrom , sameNat pto pres) of
                -- (Just argEq,Just resEq ) ->  (gcastWith argEq (gcastWith resEq (evalB $ theFun args)))
                 --_ -> throwSTE "mismatched arities in function application "
        (VNeutral neut) ->
        --- this is kinda weird
          do args <- evalB argExp
             case args  of
                      NeutTrivial proxArity realArgs ->
                           return  $ NeutApp neut  proxArity pres realArgs
                      _ -> throwSTE "make this a let, todo"


evalB (FunctionSpaceTypeExp _ _ _) = undefined
evalB (DelayType _ _) = undefined
evalB (BaseType _) = undefined
evalB (Sorts _s) = undefined
--evalB (Pure val) = return $ NeutValue val
evalB (Abs f) = return $ NeutTrivial  Proxy $ (  (VFunk   f) :* SLNil )
evalB (Return ls) = do res <- sizedMapM evalSingle ls ; return $ NeutTrivial Proxy $ fmap VNeutral res
evalB (HasType x _prox  _) = evalB x
evalB (Delay resArity resExp ) =
     do  handle<- PMV.newMutVar   (ThunkComputation resExp)
         return $  NeutTrivial (Proxy :: Proxy 1) $ (VThunk  resArity handle) :* SLNil
evalB (Force  (resExp) (proxyRes :: Proxy n) ) = case sameNat proxyRes (Proxy :: Proxy 1)  of
      Just eq -> gcastWith eq ( evalSingle (Force resExp Proxy) )
      Nothing ->  do
        {- TODO  !!: THink about proper sharing of Neutral computations -}
        {-  Because that is ignored for now, wil -}

          (resEvaled :: Neutral s 1) <- evalSingle resExp
          case resEvaled of

               --- this should be NeutralLet not a NeutForce..., maybe?
            (NeutTrivial (prar :: Proxy 1 ) ((VThunk  (pr :: Proxy m) mut) :* _)) ->
             case sameNat pr proxyRes  of
                (Just moreeq) -> gcastWith moreeq $
                  do thunkRep <- readMutVar mut
                     case thunkRep of
                        ThunkValueResult valList -> return $ gcastWith moreeq (NeutTrivial Proxy valList)
                        ThunkComputation (expr :: Exp (Value s Neutral) n) -> do
                          writeMutVar mut ThunkBlackHole
                          exprRes <- evalB expr
                          case exprRes  of
                            NeutTrivial (prox :: Proxy n) theValList ->
                              do  writeMutVar mut (ThunkValueResult theValList)
                                  return $ NeutTrivial  pr  theValList
                            neut ->
                              do  writeMutVar mut (ThunkMultiNeutralResult  neut)
                                  return neut


                        ThunkBlackHole -> throwSTE " THERE IS A BLACK HOLE,RUNNNNN, sound the alarms "
                        ThunkMultiNeutralResult  neu -> return neu
                Nothing -> throwSTE "there is a hole in reality, please report a bug"
            (NeutTrivial prar ( _  :* _ ) )   ->
                throwSTE "something thats not a thunk is being forced, thats a bug!"
            (neutForceArg) -> return $  (NeutForce  neutForceArg proxyRes)

                                  -- 3 cases, eval, black hole, or value

evalB (LetExp argExp (RawFunk _parg _pres funk)) =
            do args <- evalB argExp
               case args of
                  (NeutTrivial _prox theArgs ) -> evalB (funk theArgs)
                  _ ->undefined
                  --(Left _)  -> throwSTE "woops, RHS of a let expression should never be Neutral"
                           {-  is that True? AUDIT / FIXME?! thats a multi arity NEutral -}
evalB (CaseCon scrutinee _resTy casesMap) = do
  valScrutinee <- evalSingle scrutinee
  case valScrutinee of
    (NeutTrivial _p (v :* SLNil) ) ->
      case v of
        (VCanCase (VLit _)) ->  throwSTE "casing on literals isn't supported yet "
        (VCanCase (VConstructor tag psize vals)) ->
          case Map.lookup tag casesMap of
            (Just (SomeArityExpFun parg _pres (RawFunk _parg2 _pres2 funk))) ->
                case sameNat psize parg of
                  Just peq ->  evalB $ gcastWith peq (funk vals)
                  Nothing -> throwSTE $ "arity mismatch in case tag:" ++ show tag
                        ++ "\n branch expects arity " ++ show (natVal parg)
                        ++ "\n constructor arity was " ++ show (natVal psize)
            Nothing -> throwSTE  $ "constructor tag undefined in case: " ++ show tag
        (VThunk _p _v) -> throwSTE "error :  case analysis of thunk/closures isn't allowed"
        (VFunk _v) -> throwSTE "error : case analysis of function values/closures isn't allowed"
        (VNeutral neut ) -> return $  NeutCase  neut {-resTy-} casesMap
    --(VNeutral neut) ->
        --return $ ( VNeutral $!  NeutCase neut {- _resTy here? -} casesMap) :* SLNil
                        ---- WOAH, this is a mismatch in arity wrt normalization ... gah



evalSingle :: forall s  .  Exp  (Value s Neutral) 1 -> STE String  s   (Neutral s 1)
evalSingle (App (parg :: Proxy m) (pres :: Proxy 1 )  funExp argExp) =
    --- sweeeet/subtle use of GADT matching to name the
  case sameNat pres (Proxy :: Proxy 1) of
    Nothing -> throwSTE "impossible error, result arity 1 app with >1 result  arity, please report bug"
    (Just _) -> do
      (funVal :: Neutral s 1 ) <- evalSingle funExp
      (argVal :: (Neutral s m))  <- evalB argExp
      case (funVal,argVal) of
        (NeutTrivial  (Proxy :: Proxy 1) (VFunk (RawFunk proxArg  proxyRes  theFun) :* SLNil ),
         (NeutTrivial proxArgsList argsL )  )
           ->
             case (sameNat (Proxy :: Proxy 1) proxyRes, sameNat proxArg  proxArgsList) of
                (Just resEq, Just argEq{-, Just moreargseq-}) ->
      {-gcastWith  moreargseq -} (gcastWith resEq (gcastWith argEq (evalSingle (theFun argsL))))
                ( _result  ,  _inputArglist ) -> throwSTE "error: bad arity in runtime function application"
                            --  | GT.natVal pres == 1 = undefined
                        --  | otherwise || GT.natVal pres /= 1 = throwSTE "WAT, we hosed"
evalSingle (Abs fun ) = return $ NeutTrivial Proxy $  (VFunk fun :* SLNil)
evalSingle (FunctionSpaceTypeExp _ _ _) = undefined ---
evalSingle (DelayType _ _) = undefined --- see BaseType and FunctionSpace
evalSingle (BaseType _bt) = undefined --- need normalized type expressions
evalSingle (Sorts _s) = undefined --- need normalized type expressions
--evalSingle (Pure v) = case v of
--                        VNeutral n -> return n
--                        _ -> return $ NeutTrivial (Proxy :: Proxy 1) (v :* SLNil)
--evalSingle (Abs f) = return $ (VNormal $! VFunk f )
--evalSingle (Return (x :*  _ )) = evalSingle x
--evalSingle (Return (x :* _ :* _ )) = evalSingle x --- rejects
evalSingle (Return (x :* SLNil)) = evalSingle x
evalSingle (Return (_ :* _ )) = throwSTE "error: impossible branch for evalSingle of Return"
                      ---  This second case shouldnt be needed
                      --- if the type nat solver also helped the coverage checker
                        --- is that a gap in type solver <--- > new coverage checker??
--evalSingle  (Return ls) = sizedMapM (\ x -> do  (y :* SLNil) <- evalB (x :* SLNil); return y ) ls
evalSingle (HasType x _prox _ty {- type should be normalized too -} )  =  do
        res <- evalB x
        case res of
            (NeutTrivial (Proxy :: Proxy 1 )((VNeutral v) :* SLNil)) -> return v
            (NeutTrivial (Proxy :: Proxy 1 )(v :* SLNil)) -> return res
            (NeutTrivial Proxy (_ :* _)) -> throwSTE "bad bad arity for HastypeExpr in evalSingle"
            neut -> return res  {- not sure if this is right, audit!! TODO  -}
evalSingle (Delay (resArity :: Proxy n) (resExp :: (Exp (Value s Neutral) n)) ) =
   {- just copy the code from evalB of Delay, thats simpler ... -}
 case sameNat (Proxy :: Proxy n ) (Proxy :: Proxy 1) of
    Nothing -> throwSTE  $ "bad arity in delay result, expect arity 1, got "  ++ show (natVal resArity)
    Just eqProof -> gcastWith eqProof
          (do
            theRes <- evalB resExp
            case theRes of
              (NeutTrivial (Proxy :: Proxy 1) (theVal :* SLNil)) -> return $ theRes
              (NeutTrivial Proxy   _) ->
                  throwSTE "literally impossible branch happened, report a bug in ghc and hopper both"
              neut {- arity 1!! -} -> return $  theRes

                )
 --    undefined {- allocate mutable variable etc -}

evalSingle (Force proxyRes resExp ) =  undefined -- check result arity is one first
evalSingle (LetExp argExp bodyBind) = undefined
evalSingle (CaseCon scrutinee _resTy casesMap) = undefined

reflect :: (Value s Neutral) -> STE String s NominalExp
reflect = undefined

reify :: NominalExp -> STE String s (Exp (Value s Neutral) 1)
reify = undefined
