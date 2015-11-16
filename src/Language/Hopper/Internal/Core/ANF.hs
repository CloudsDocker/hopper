{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable,DeriveAnyClass #-}
-- {-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE RankNTypes #-}
-- {-# LANGUAGE KindSignatures #-}
-- {-# LANGUAGE DeriveGeneric #-}

module Language.Hopper.Internal.Core.ANF  where

import Language.Hopper.Internal.Core.Type
import Language.Hopper.Internal.Core.Literal
import Data.Text (Text)
import Data.Data
-- import Data.Word (Word64)

import  Control.Monad
import Prelude.Extras
import Bound
import Language.Hopper.Internal.Core.Term




scopedAnf2ScopedExp :: (Ord b, Ord ty, Ord a, Monad m )=> (Text -> m (Exp ty a))-> (ty -> ConstrId -> m (Exp ty a))-> Scope b (ANF ty) a ->  m (Scope b (Exp ty) a)
scopedAnf2ScopedExp f c  scp= Scope <$>(  anf2Exp (fmap  (V . F) . f) (\ ty con -> fmap (V .  F) $ c ty con)   =<< (traverse (traverse ( anf2Exp f c )) $ unscope scp ))

anf2Exp :: forall a m ty . (Ord ty, Ord a, Monad m )=> (Text -> m (Exp ty a))-> (ty -> ConstrId -> m (Exp ty a))-> ANF ty a -> m (Exp ty a)
anf2Exp _f _c (ReturnNF a) = return (V a)
anf2Exp f  c (LetNF mname mtype rhs scp) =
    do  rhsExp <- rhs2Exp f c rhs
        bod :: Scope (Maybe Text) (Exp ty) a  <-  scopedAnf2ScopedExp f c scp
        -- (anf2Exp (fmap F . f) (fmap F . c))  $ unscope scp
        -- bod2 :: <- Scope <$> traverse ( traverse . traverse (anf2Exp f c)) bod1
        return (Let mname mtype rhsExp bod)
        -- return undefined
anf2Exp f _c (TailCallANF app) = appANF2Exp f  app

rhs2Exp :: (Ord ty, Ord a, Monad m )=> (Text -> m (Exp ty a))->
                            (ty -> ConstrId -> m (Exp ty a))-> AnfRHS ty a -> m (Exp ty a)
rhs2Exp _f _c (SharedLiteral l) = return $ ELit l
rhs2Exp _f c (ConstrApp ty conid lsargs) = do   conname <- c ty conid
                                                return (conname :@  fmap V lsargs)
rhs2Exp f c (AllocateThunk e) = do  newExp <- anf2Exp f c e
                                    return (Delay newExp)
rhs2Exp f c (AllocateClosure binders scp) = do  fixedScp <- scopedAnf2ScopedExp f c scp
                                                return (Lam binders fixedScp)
rhs2Exp f _c (NonTailCallApp app) = appANF2Exp f app



appANF2Exp :: forall a m ty . ( Ord a, Monad m )=> (Text -> m (Exp ty a)) -> AppANF ty a -> m (Exp ty a)
appANF2Exp _f  (EnterThunk a) = return $ Force (V a)
appANF2Exp _f  (FunApp a argLS) = return $  V a :@ map V argLS
appANF2Exp f   (PrimApp txt argLS) = do  primName <- f txt
                                         return $  primName :@ map V argLS

-- at runtime 'ConstrId' is mapped to a tag???
newtype ConstrId  = ConstrId { unConstrId :: Text } deriving (Eq, Show,Data,Typeable,Ord,Read)

-- | the right hand side of a LetNF, aka 'AnfRHS' is the point where heap allocation of thunks happens
-- the only other
data AnfRHS ty a = SharedLiteral !Literal -- we currently do not have any fixed size literal types
                                          -- so for now all literals are heap allocated
                                          -- this will change once we add support for stuff like
                                          -- Double or Word64
                 | ConstrApp !ty !ConstrId [a]
                 | AllocateThunk (ANF ty a) -- Thunks share their evaluations
                --  | EvaluateThunk !a       -- Thunk evaluation is a special
                --                           -- no arg lambda plus sharing
                                            -- thunks and closure should
                                            -- record their free variables???
                 | AllocateClosure ![(Text,Type ty,RigModel)] -- arity >=0
                                   (Scope Text (ANF ty)  a)  -- should we have global table of
                                                              -- "pointers" to lambdas? THINK ME + FIX ME

                 | NonTailCallApp (AppANF ty a) -- control stack allocation; possibly heap allocation


   deriving (Ord,
    Functor,
    Foldable,
    Traversable,
    Typeable,
    Data,
    Eq,
    Read,
    Show)
instance Eq ty => Eq1 (AnfRHS ty)
instance Show ty => Show1 (AnfRHS ty)
instance Ord ty => Ord1 (AnfRHS ty)
instance Read ty => Read1 (AnfRHS ty)

instance Eq2 AnfRHS
instance Show2 AnfRHS
instance Ord2 AnfRHS
instance Read2 AnfRHS
-- data ArgANF ty a = ArgVar a | ArgLit !Literal


data AppANF ty a = EnterThunk !a
                 | FunApp !a ![a]
                 | PrimApp !Text ![a]
        deriving ( Ord,
         Functor,
         Foldable,
         Traversable,
         Typeable,
         Data,
         Eq,
         Read,
         Show)

instance Eq ty => Eq1 (AppANF ty)
instance Show ty => Show1 (AppANF ty)
instance Ord ty => Ord1 (AppANF ty)
instance Read ty => Read1 (AppANF ty)

instance Eq2 AppANF
instance Show2 AppANF
instance Ord2 AppANF
instance Read2 AppANF


data ANF ty a
    = ReturnNF  !a -- !(Atom ty a)
    | LetNF (Maybe Text) (Maybe(Type ty, RigModel)) (AnfRHS ty a) (Scope (Maybe Text) (ANF ty) a)
    -- | LetNFMulti ![AnfRHS ty a] !(Scope Word64 (ANF ty) a)
    | TailCallANF (AppANF ty a)
    -- future thing will have | LetNFRec maybe?
    deriving (Ord,
      Functor,
      Foldable,
      Traversable,
      Typeable,
      Data,
      Eq,
      Read,
      Show)
instance Eq ty => Eq1 (ANF ty)
instance Show ty => Show1 (ANF ty)
instance Ord ty => Ord1 (ANF ty)
instance Read ty => Read1 (ANF ty)

instance Eq2 ANF
instance Show2 ANF
instance Ord2 ANF
instance Read2 ANF

-- l2rJoinANF :: forall ty a . (ANF ty (ANF ty a)) -> (ANF ty a)
-- l2rJoinANF (ReturnNF a) = a
-- l2rJoinANF (LetNF rhs bod) = l2rCanonicalRHS rhs (Scope $ fmap (fmap l2rJoinANF) $ unscope bod)
--
-- l2rCanonicalRHS :: AnfRHS ty (ANF ty a)
--                 -> ((Scope () (ANF ty) a)
--                 -> ANF ty a)
-- l2rCanonicalRHS (AllocateThunk e) scp = LetNF (AllocateThunk $ l2rJoinANF e) scp
-- l2rCanonicalRHS (SharedLiteral l) scp = LetNF (SharedLiteral l) scp
-- l2rCanonicalRHS (AllocateClosure ls bod) scp = LetNF (AllocateClosure ls $ Scope $ fmap (fmap l2rJoinANF) $ unscope bod) scp

{-
AUDIT: should we just be doing the too / from scope functions?

-}
-- flattenUnderScope :: Scope b (ANF ty) (ANF ty a) -> Scope b (ANF ty) a
-- flattenUnderScope = Scope . fmap (fmap danvyANF) . unscope



zoomToTailPosition :: forall a ty . (forall c . c -> ANF ty c) ->  ANF ty a -> ANF ty a
zoomToTailPosition f (ReturnNF a)  = f a
zoomToTailPosition f (TailCallANF app)  = LetNF Nothing Nothing (NonTailCallApp app)
                                           (Scope $ f (B Nothing ))
zoomToTailPosition f (LetNF mebeName mebeCut  rhs bod)  =   LetNF  mebeName mebeCut rhs
                                          (Scope $ (fmap $ fmap $ zoomToTailPosition f) $ unscope bod)
-- zoomToTailPosition f (LetNFMulti rhss bod) = LetNFMulti rhss
--                     (Scope $ (fmap $ fmap $ zoomToTailPosition f) $ unscope bod)
--
-- danvyANF :: (ANF ty (ANF ty a)) -> ANF ty a
-- danvyANF (ReturnNF a) = a
-- danvyANF (TailCallANF app) = danvyTailCallANF app
-- danvyANF (LetNF rhs bod) = danvyRHS rhs (\r -> LetNF r $  flattenUnderScope bod)
--
-- danvyRHS :: (AnfRHS ty (ANF ty a)) ->(AnfRHS ty a -> ANF ty a) -> ANF ty a
-- danvyRHS (SharedLiteral l)  f =  f $ SharedLiteral l
-- danvyRHS (AllocateThunk expr) f = f $ AllocateThunk $ danvyANF expr
-- danvyRHS (AllocateClosure args scp) f = f $ AllocateClosure args (flattenUnderScope scp)
-- danvyRHS (NonTailCallApp app) f = danvyNotTailCallANF app  f
--
--
-- danvyExp2RhsANF :: (ANF ty a) -> ( a -> ANF ty a) -> ANF ty a
-- danvyExp2RhsANF = error "{ this is TERRRRIBLEEEEEEE }"
-- -- danvyExp2RhsANF (ReturnNF v) f = f v
-- -- danvyExp2RhsANF (TailCallANF app) f = danvyNotTailCallANF app (\ rhs -> LetNF rhs )
--
--
-- danvyTailCallANF :: (AppANF ty (ANF ty a)) {- } -> (AppANF ty a -> ANF ty a )-} -> ANF ty a
-- danvyTailCallANF (EnterThunk (ReturnNF x)) =  LetNF (NonTailCallApp (EnterThunk x))
--                                                   (Scope  $ ReturnNF(B ()))
-- danvyTailCallANF (EnterThunk (TailCallANF app)) =
--                                             LetNF
--                                               (NonTailCallApp app)
--                                               (Scope $ (
--                                                 ( LetNF (NonTailCallApp (EnterThunk (B ())))
--                                                       (Scope $ ReturnNF (B () ))
--                                                       )))
-- danvyTailCallANF (EnterThunk lt@(LetNF _ _))=
--           zoomToTailPosition (\ x -> LetNF (NonTailCallApp $ EnterThunk x )
--                                             (Scope $ ReturnNF (B()))
--                                           )
--                               lt
--
-- danvyNotTailCallANF :: (AppANF ty (ANF ty a)) -> ( AnfRHS ty a -> ANF ty a) -> ANF ty a
-- danvyNotTailCallANF (EnterThunk a) f = danvyExp2RhsANF a (\ var -> f $ NonTailCallApp
--                                                                      $ EnterThunk var  )
{- traverse from right to left using Reverse or Backwards applicative
over State, accumulating continuations of the inner scopes that are the
later evaluation steps
  -}

instance Applicative (ANF ty) where
  pure  = \x -> ReturnNF  x
  (<*>) = ap

instance Monad (ANF ty) where
  (ReturnNF var) >>= f = f var


 {- (afun :@@ aargs) >>= f =
        LetNF subst'dArgs :: forall a b .  (a -> ANF ty b) -> [Atom ty a]-> [ANF ty b]
            subst'dArgs  g  ls = fmap (unVar . fmap g) ls
            foldrList :: forall a b . (a -> b -> b) -> b -> [a] -> b
            foldrList = foldr
            cps'dArgs :: _sdfdsfdsf
            cps'dArgs = foldrList  cpsStacking id  (subst'dArgs f aargs)
            -- cpsStacking :: forall  a  . ( ) -> (a -> ANF ty a) -> (a -> ANF ty a)
            cpsStacking = _lalala
        in  (f $ unVar $ afun) `cpsStacking` cps'dArgs-}
  -- (LetNF aRHS aBod) >>= f = _dderp
  -- (ReturnNF (AtomicLit l)) >>= _f = ReturnNF $ AtomicLit l
  -- (ReturnNF (AtomLam bs bod)) >>= f = ReturnNF $ AtomLam bs (bod >>>= f)
  --( ( ) :@@ )

  -- return = V
  --V a         >>= f = f a
  --Delay e     >>= f = Delay $ e >>= f
  --Force e     >>= f = Force $ e >>= f
  --ELit e      >>= _f = ELit e -- this could also safely be a coerce?
  --(x :@ y)    >>= f = (x >>= f) :@ (y >>= f)
  --Lam t  e    >>= f = Lam t (e >>>= f)
  --LetNF t bs  b >>= f = LetNF t (  bs >>= f)  (b >>>= f)
