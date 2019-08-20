-- | Comparison protocols

module Comparison where

import Universum

import Control.Concurrent.Async (concurrently)
import Data.Bits (testBit)
import Data.List ((!!))
import qualified Data.List.NonEmpty as NE
import System.IO (hFlush, stdout)
import System.Random (randomRIO)
import System.ZMQ4

import Hacl
import Utils

zsend :: Socket Dealer -> ByteString -> IO ()
zsend sock bs = send sock [] bs

zsendMulti :: Socket Dealer -> [ByteString] -> IO ()
zsendMulti sock bs = sendMulti sock $ NE.fromList bs

zreceive :: Socket Dealer -> IO ByteString
zreceive = receive

zreceiveMulti :: Socket Dealer -> IO [ByteString]
zreceiveMulti sock = receiveMulti sock

----------------------------------------------------------------------------
-- DGK
----------------------------------------------------------------------------

measureTimeSingle' :: Text -> IO x -> IO x
measureTimeSingle' _l a = a
--    measureTimeSingle l a

-- do
--   send sock [] "init"
-- before calling it
-- Server talks to us first
-- | Compute r <= c jointly. Client has r, server has c.
dgkClient ::
       (Pahe sDGK, Pahe sGM)
    => Socket Dealer
    -> PahePk sDGK
    -> PahePk sGM
    -> Int
    -> [Integer]
    -> IO (PaheCiph sGM)
dgkClient sock pkDGK pkGM l rs = do
    log "Client: dgk started"

    let rsLen = length rs
    when (rsLen > paheK pkDGK) $ error "dgk rsLen is too big"

    log "Client: encoding rbits"
    let !rbits = map (\i -> map (\c -> bool 0 1 $ testBit c i) rs) [0..l-1]
    --log $ "Client rbits: " <> show rbits
    encRBits <-
        measureTimeSingle' "enc rBits" $
        mapM (paheEnc pkDGK) rbits


    let !bitmaskNeg = map (\x -> 1 - x) <$> rbits
    log "Client: receiving"
    csRaw <- zreceiveMulti sock
    log $ "Client: received: " <> show (length csRaw)
    cs <- mapM (paheFromBS pkDGK) csRaw
    log "Client: decoded"

    (ciRaw,s0) <- do
      measureTimeSingle' "DGK client heavy part" $ do
        log "Client: computing xors"
        xors <-
         measureTimeSingle' "Computing XORs" $
          forM (cs `zip` bitmaskNeg `zip` rbits) $ \((ci,bmNegI),rbitsI) -> do

            -- ci * maskNeg + (1-ci) * mask
            a <- paheSIMDMulScal pkDGK ci bmNegI
            oneMinCi <- paheSIMDSub pkDGK (paheOne pkDGK) ci
            c <- paheSIMDMulScal pkDGK oneMinCi rbitsI
            ret <- paheSIMDAdd pkDGK a c

            paheFree' [a,oneMinCi,c]

            pure ret
        log "Client: computed xors"

        --log "XORS: "
        --print =<< mapM (paheDec skDGK) xors

        delta <- replicateM rsLen (randomRIO (0,1))
        deltaEnc <- paheEnc pkDGK delta
        let s0 = map (\i -> 1 - 2 * i) delta
        log $ "Client: s = " <> show s0
        s <- paheEnc pkDGK s0

        log "Client: computing xor sums"
        let computeXorSums i prev = do
                nextXorSum <- paheSIMDAdd pkDGK prev (xors !! i)
                xorsTail <- if i == 0 then pure [] else computeXorSums (i-1) nextXorSum
                pure $ nextXorSum : xorsTail
        xorsums <- reverse <$> computeXorSums (l-1) (paheZero pkDGK)

        --log "XOR SUBS: "
        --print =<< mapM (paheDec skDGK) xorsums

        log "Client: computing cis"
        ci <- forM [0..l-1] $ \i -> do
            a <- paheSIMDAdd pkDGK s (encRBits !! i)
            b <- paheSIMDSub pkDGK a (cs !! i)
            paheFree a

            if i == l-1 then pure b else do
                xorsum3 <- paheSIMDMulScal pkDGK (xorsums !! (i+1)) $ replicate rsLen 3
                ret <- paheSIMDAdd pkDGK b xorsum3
                paheFree' [xorsum3,b]
                pure ret

        xorsumFull3 <- paheSIMDMulScal pkDGK (xorsums !! 0) $ replicate rsLen 3
        cLast <- paheSIMDAdd pkDGK deltaEnc xorsumFull3

        let ciRaw = cLast : ci

        paheFree' $ deltaEnc : s : xorsumFull3 : (xorsums ++ xors)

        pure (ciRaw,s0)

    --log "CIs: "
    --print =<< mapM (paheDec skDGK) (cLast : ci)
    log "CIs were computed"

    --ciShuffled <- shuffle blinded
    ciShuffled <-
      measureTimeSingle' "client shuffling" $
      if rsLen == 1 then shuffle =<< mapM (paheMultBlind pkDGK) ciRaw else do
        blinded <- mapM (paheMultBlind pkDGK) ciRaw
        let oneMasks = map (\i -> replicate i 0 ++ [1]) [0..rsLen - 1]
        shortZero <- paheEnc pkDGK $ replicate rsLen 0

        rows :: [[PaheCiph sDGK]] <-
            measureTimeSingle' "client shuffling mults" $
            forM oneMasks $ \curMask ->
                mapM (\x -> paheSIMDMulScal pkDGK x curMask) blinded

        rowsShuffled <-
            measureTimeSingle' "client shuffling shuffling" $
            forM rows shuffle


        ret <- measureTimeSingle' "client shuffling additions" $
          foldrM (\acc b -> mapM (\(x,y) -> do
                                       ret <- paheSIMDAdd pkDGK x y
                                       --paheFree' [x,y]
                                       pure ret)
                                 (zip acc b))
            (replicate (l+1) shortZero) rowsShuffled

        paheFree' $ shortZero : blinded

        pure ret

    --log "CIs shuffled/blinded: "
    --print =<< mapM (paheDec skDGK) ciShuffled

    zsendMulti sock =<< mapM (paheToBS pkDGK) ciShuffled
    log "Client: sent, waiting"
    zs <- paheFromBS pkGM =<< zreceive sock
    log "Client: computing eps"

    let compeps = measureTimeSingle' "DGK client compeps" $ do
          let sMask = map (bool 1 0 . (== 1)) s0
          let sMaskNeg = map (\x -> 1 - x) sMask
          -- zs * s + (1-zs) * neg s
          a <- paheSIMDMulScal pkGM zs sMask
          oneMinZs <- paheSIMDSub pkGM (paheOne pkGM) zs
          c <- paheSIMDMulScal pkGM oneMinZs sMaskNeg
          r <- paheSIMDAdd pkGM a c
          paheFree' [a,oneMinZs,c]
          pure r

    eps <- compeps

    paheFree' $ encRBits ++ cs ++ ciRaw
    paheFree zs

    log "Client: dgk ended"
    pure eps

dgkServer ::
       (Pahe sDGK, Pahe sGM)
    => Socket Dealer
    -> PaheSk sDGK
    -> PaheSk sGM
    -> Int
    -> [Integer]
    -> IO ()
dgkServer sock skDGK skGM l cs = do
    log "Server: dgk started"
    let pkDGK = paheToPublic skDGK
    let pkGM = paheToPublic skGM
    let csLen = length cs

    let cbits = map (\i -> map (\c -> bool 0 1 $ testBit c i) cs) [0..l-1]
    --log $ "Server cbits: " <> show cbits

    log "Server: encrypting/encoding cbits"
    cbitsEncrypted <- mapM (paheEnc pkDGK) cbits
    cbitsToSend <- mapM (paheToBS pkDGK) cbitsEncrypted

    log $ "Sending cbits to client"
    zsendMulti sock cbitsToSend
    paheFree' cbitsEncrypted
    log $ "Server sent"

    es <- mapM (paheFromBS pkDGK) =<< zreceiveMulti sock
    log $ "Server: computing zeroes"
    esZeroes <-
        measureTimeSingle' "DGK isZero testing" $
        mapM (fmap (take csLen) . paheIsZero skDGK) es
    let zeroes = map (bool 0 1) $
                 foldr (\e acc -> map (uncurry (&&)) $ zip e acc)
                       (replicate csLen True)
                       (map not <$> esZeroes)

    log $ "Server zeroes: " <> show zeroes

    enczeroes <- paheEnc pkGM zeroes
    zsend sock =<< paheToBS pkGM enczeroes
    paheFree' es
    paheFree enczeroes

    log "Server: dgk exited"


----------------------------------------------------------------------------
-- Secure Comparison
----------------------------------------------------------------------------

-- | Compute y <= x jointly with secret inputs. Client has r, server has c.
secureCompareClient ::
       (Pahe sTop, Pahe sDGK, Pahe sGM)
    => Socket Dealer
    -> PahePk sTop
    -> PahePk sDGK
    -> PahePk sGM
    -> Int
    -> Int -- how many to SIMD compare
    -> PaheCiph sTop
    -> PaheCiph sTop
    -> IO (PaheCiph sGM)
secureCompareClient sock pkTop pkDGK pkGM l m x y = do
  measureTimeSingle' "secure compare client" $ do

    log "Client: secureCompare started"
    when (m > paheK pkDGK) $ error "Secure compare: m is too big"

    rhos::[Integer] <- replicateM m $ randomRIO (0, 2^(l + lambda) - 1)
    s0 <- paheEnc pkTop (map (+(2^l)) rhos)
    s1 <- paheSIMDAdd pkTop x s0
    gamma <- paheSIMDSub pkTop s1 y

    zsend sock =<< paheToBS pkTop gamma
    paheFree' [gamma,s0,s1]

    cDiv2l <- paheFromBS pkGM =<< zreceive sock

    eps <- dgkClient sock pkDGK pkGM l $ map (`mod` (2^l)) rhos
    epsNeg <- paheSIMDSub pkGM (paheOne pkGM) eps

    rDiv2l <- paheEnc pkGM $ map (`div` (2^l)) rhos
    rPlusEpsNeg <- paheSIMDAdd pkGM rDiv2l epsNeg
    delta <- paheSIMDSub pkGM cDiv2l rPlusEpsNeg

    paheFree' [eps,epsNeg,rDiv2l,rPlusEpsNeg]

    log "Client: secureCompare exited"
    pure delta

secureCompareServer ::
       (Pahe sTop, Pahe sDGK, Pahe sGM)
    => Socket Dealer
    -> PaheSk sTop
    -> PaheSk sDGK
    -> PaheSk sGM
    -> Int
    -> Int
    -> IO ()
secureCompareServer sock skTop skDGK skGM l m = do
    let pkTop = paheToPublic skTop
    let pkGM = paheToPublic skGM
    log "Server: securecompare started"

    gamma0 <- paheFromBS pkTop =<< zreceive sock
    gamma <- paheDec skTop gamma0
    paheFree gamma0
    let cMod2 = map (`mod` (2^l)) $ take m gamma
    let cDiv2 = map (`div` (2^l)) $ take m gamma
    cDiv2Enc <- paheEnc pkGM cDiv2
    zsend sock =<< (paheToBS pkGM cDiv2Enc)
    paheFree cDiv2Enc

    dgkServer sock skDGK skGM l cMod2

    log "Server: securecompare exited"

----------------------------------------------------------------------------
-- Tests
----------------------------------------------------------------------------

_testCmp ::
    forall sTop sDGK sGM.
    (Pahe sTop, Pahe sDGK, Pahe sGM) =>
    Int -> Int -> Socket Dealer -> Socket Dealer -> IO ()
_testCmp tries k req rep = do
    putTextLn $ "_testCMP, k = " <> show k

    -- bit size of numbers we compare
    let l = 64
--    m <- randomRIO (1,k)

    -- system used to carry long secureCompare results
    skTop <- paheKeyGen @sTop k (2^(lambda + l + 100))
    --let skTop = skDGK
    let pkTop = paheToPublic skTop

    -- system used for DGK comparison
    --skDGK <- paheKeyGen @PailSep k (2^(lambda+l))
    skDGK <- paheKeyGen @sDGK k (5 + 3 * fromIntegral l)
    let pkDGK = paheToPublic skDGK

    -- system used to carry QR results
    --skGM <- paheKeyGen @DgkCrt k 5 -- (2^(l+5))
    skGM <- paheKeyGen @sGM k 5 -- (2^(l+5))
    --let skGM = skDGK
    let pkGM = paheToPublic skGM

    let testCompare m = do
            xs <- replicateM m $ randomRIO (0,2^l-1)
            ys <- replicateM m $ randomRIO (0,2^l-1)
            let expected = map (\(x,y) -> x >= y) $ zip xs ys

            xsEnc <- paheEnc pkTop xs
            ysEnc <- paheEnc pkTop ys

            ((gamma,()),timing) <-
                measureTimeSingle' "SecureCompare" $
                measureTimeRet $
                concurrently
                (secureCompareClient req pkTop pkDGK pkGM l m xsEnc ysEnc)
                (secureCompareServer rep skTop skDGK skGM l m)
            putText "." >> hFlush stdout

            secCompRes <- paheDec skGM gamma
            unless (map (bool 0 1) expected `isPrefixOf` secCompRes) $ do
                print xs
                print ys
                putTextLn $ "Expected: " <> show expected
                putTextLn $ "Got:      " <> show secCompRes
                putTextLn $ "          " <> show (map (==1) secCompRes)
                error "Mismatch"

            pure timing

    let testDGK m = do
            cs <- replicateM m $ randomRIO (0,2^l-1)
            rs <- replicateM m $ randomRIO (0,2^l-1)
            let expected = map (\(c,r) -> r <= c) $ zip cs rs

            ((eps,()),timing) <-
                measureTimeSingle' "dgk" $
                measureTimeRet $
                concurrently
                (dgkClient req pkDGK pkGM l rs)
                (dgkServer rep skDGK skGM l cs)
            putText "." >> hFlush stdout

            dgkRes <- map (== 1) <$> paheDec skGM eps
            unless (expected `isPrefixOf` dgkRes) $ do
                print cs
                print rs
                putTextLn $ "Expected: " <> show expected
                putTextLn $ "Got:      " <> show dgkRes
                error "Mismatch"
            pure timing


    let finTest :: Int -> IO ()
        finTest m = do
            timingsDGK <- replicateM tries $ testDGK m
            putTextLn $ "\n --- DGK m = " <> show m
                <> " is " <> show (average timingsDGK) <> " mcs" <>
                (if m == 1 then "" else " on average: " <> show (average timingsDGK `div` fromIntegral m))

            timingsSC <- replicateM tries $ testCompare m
            putTextLn $ "\n --- SecureCompare m = " <> show m
                <> " is " <> show (average timingsSC) <> " mcs" <>
                (if m == 1 then "" else " on average: " <> show (average timingsSC `div` fromIntegral m))

    finTest 1
--    finTest 2
--    finTest 3
--    finTest 4
--    finTest 6
--    finTest 8
--    finTest 10
--    finTest 12
--    finTest 14
--    finTest 16
    when (k /= 1) $ finTest k
--    finTest 24
--    finTest 28
--    finTest 32

_testCmpInproc ::
    forall sTop sDGK sGM.
    (Pahe sTop, Pahe sDGK, Pahe sGM) =>
    Int -> Int -> IO ()
_testCmpInproc tries k =
    withContext $ \ctx ->
    withSocket ctx Dealer $ \req ->
    withSocket ctx Dealer $ \rep -> do
       bind rep "inproc://argmax"
       connect req "inproc://argmax"
       _testCmp @sTop @sDGK @sGM tries k req rep
