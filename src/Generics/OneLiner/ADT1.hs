-----------------------------------------------------------------------------
-- |
-- Module      :  Generics.OneLiner.ADT1
-- Copyright   :  (c) Sjoerd Visscher 2012
-- License     :  BSD-style (see the file LICENSE)
--
-- Maintainer  :  sjoerd@w3future.com
-- Stability   :  experimental
-- Portability :  non-portable
--
-- This module is for writing generic functions on algebraic data types 
-- of kind @* -> *@. 
-- These data types must be an instance of the `ADT1` type class.
-- 
-- Here's an example how to write such an instance for this data type:
--
-- @
-- data T a = A [a] | B a (T a)
-- @
--
-- @
-- instance `ADT1` T where
--   `ctorIndex` A{} = 0
--   `ctorIndex` B{} = 1
--   type `Constraints` T c = (c [], c T)
--   `buildsRecA` `For` par sub rec = 
--     [ (`ctor` \"A\", A `<$>` sub (`component` (\\(A l) -> l))
--     , (`ctor` \"B\", B `<$>` par (`param` (\\(B a _) -> a)) `<*>` rec (`component` (\\(B _ t) -> t)))
--     ]
-- @
-----------------------------------------------------------------------------
{-# LANGUAGE 
    RankNTypes
  , TypeFamilies
  , TypeOperators
  , ConstraintKinds
  , FlexibleInstances
  , DefaultSignatures
  , ScopedTypeVariables
  #-}
module Generics.OneLiner.ADT1 (

    -- * Re-exports
    module Generics.OneLiner.Info
  , Constraint
    -- | The kind of constraints
  
    -- * The @ADT1@ type class
  , ADT1(..)
  , For(..)
  , Extract(..)
  , (:~>)(..)
  
    -- * Helper functions
  , (!)
  , (!~)
  , at
  , param
  , component
  
  -- * Derived traversal schemes
  , builds
  , mbuilds
  
  ) where

import Generics.OneLiner.Info

import GHC.Prim (Constraint)
import Control.Applicative
import Data.Functor.Identity
import Data.Functor.Constant
import Data.Monoid

import Data.Maybe (fromJust)


newtype f :~> g = Nat { getNat :: forall x. f x -> g x }
newtype Extract f = Extract { getExtract :: forall x. f x -> x }


-- | Tell the compiler which class we want to use in the traversal. Should be used like this:
--
-- > (For :: For Show)
--
-- Where @Show@ can be any class.
data For (c :: (* -> *) -> Constraint) = For

-- | Type class for algebraic data types of kind @* -> *@. Minimal implementation: `ctorIndex` and either `buildsA`
-- if the type @t@ is not recursive, or `buildsRecA` if the type @t@ is recursive.
class ADT1 t where

  -- | Gives the index of the constructor of the given value in the list returned by `buildsA` and `buildsRecA`.
  ctorIndex :: t a -> Int
  ctorIndex _ = 0

  -- | The constraints needed to run `buildsA` and `buildsRecA`. 
  -- It should be a list of all the types of the subcomponents of @t@, each applied to @c@.
  type Constraints t c :: Constraint
  buildsA :: (Constraints t c, Applicative f)
          => For c -- ^ Witness for the constraint @c@.
          -> (FieldInfo (Extract t) -> f b)
          -> (forall s. c s => FieldInfo (t :~> s) -> f (s b))
          -> [(CtorInfo, f (t b))]
          
  default buildsA :: (c t, Constraints t c, Applicative f)
                  => For c
                  -> (FieldInfo (Extract t) -> f b)
                  -> (forall s. c s => FieldInfo (t :~> s) -> f (s b))
                  -> [(CtorInfo, f (t b))]
  buildsA for param sub = buildsRecA for param sub sub 

  buildsRecA :: (Constraints t c, Applicative f)
             => For c -- ^ Witness for the constraint @c@.
             -> (FieldInfo (Extract t) -> f b)
             -> (forall s. c s => FieldInfo (t :~> s) -> f (s b))
             -> (FieldInfo (t :~> t) -> f (t b))
             -> [(CtorInfo, f (t b))]
  buildsRecA for param sub _ = buildsA for param sub

-- | `buildsA` specialized to the `Identity` applicative functor.
builds :: (ADT1 t, Constraints t c) 
       => For c
       -> (FieldInfo (Extract t) -> b)
       -> (forall s. c s => FieldInfo (t :~> s) -> s b)
       -> [(CtorInfo, t b)]
builds for f g = fmap runIdentity <$> buildsA for (Identity . f) (Identity . g)

-- | `buildsA` specialized to the `Constant` applicative functor, which collects monoid values @m@.
mbuilds :: forall t c m. (ADT1 t, Constraints t c, Monoid m) 
        => For c
        -> (FieldInfo (Extract t) -> m)
        -> (forall s. c s => FieldInfo (t :~> s) -> m)
        -> [(CtorInfo, m)]
mbuilds for f g = fmap getConstant <$> ms
  where
    ms :: [(CtorInfo, Constant m (t b))]
    ms = buildsA for (Constant . f) (Constant . g)

-- | Get the value from the result of one of the @builds@ functions that matches the constructor of @t@.
at :: ADT1 t => [(c, a)] -> t b -> a
at as t = snd (as !! ctorIndex t)

param :: (forall a. t a -> a) -> FieldInfo (Extract t)
param f = FieldInfo (Extract f)

component :: (forall a. t a -> s a) -> FieldInfo (t :~> s)
component f = FieldInfo (Nat f)

infixl 9 !
(!) :: t a -> FieldInfo (Extract t) -> a
t ! info = getExtract (project info) t

infixl 9 !~
(!~) :: t a -> FieldInfo (t :~> s) -> s a
t !~ info = getNat (project info) t


instance ADT1 Maybe where
  
  ctorIndex Nothing = 0
  ctorIndex Just{}  = 1
  
  type Constraints Maybe c = ()
  buildsA For f _ = 
    [ (ctor "Nothing", pure Nothing)
    , (ctor "Just", Just <$> f (param fromJust))
    ]
  
instance ADT1 [] where
  
  ctorIndex [] = 0
  ctorIndex (_:_) = 1 
  
  type Constraints [] c = c []
  buildsRecA For p _ r = 
    [ (ctor "[]", pure [])
    , (CtorInfo ":" False (Infix RightAssociative 5), (:) <$> p (param head) <*> r (component tail))
    ]