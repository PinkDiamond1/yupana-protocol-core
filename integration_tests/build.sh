#!/bin/sh

mkdir -p integration_tests/compiled
docker run -v $PWD:$PWD --rm -i ligolang/ligo:0.35.0 compile contract $PWD/contracts/main/yToken.ligo  > integration_tests/compiled/yToken.tz

docker run -v $PWD:$PWD --rm -i ligolang/ligo:0.35.0 compile contract $PWD/contracts/main/priceFeed.ligo  > integration_tests/compiled/priceFeed.tz

mkdir -p integration_tests/compiled/lambdas

DIR=integration_tests/compiled/lambdas/use
mkdir -p $DIR
for i in 0,mint \
        1,redeem \
        2,borrow \
        3,repay \
        4,liquidate \
        5,enterMarket \
        6,exitMarket \
        7,setAdmin \
        8,withdrawReserve \
        9,setTokenFactors \
        10,setGlobalFactors \
        11,setBorrowPause \
         ; do 

    IDX=${i%,*};
    FUNC=${i#*,};
    echo $IDX-$FUNC;

    docker run -v $PWD:$PWD --rm -i ligolang/ligo:0.35.0 compile expression pascaligo --michelson-format json --init-file $PWD/contracts/main/yToken.ligo "SetUseAction(record index = ${IDX}n; func = Bytes.pack(${FUNC}); end)" > $PWD/$DIR/${IDX}-${FUNC}.json
done

DIR=integration_tests/compiled/lambdas/token
mkdir -p $DIR
for i in 0,transfer \
        1,update_operators \
        2,getBalance \
        3,get_total_supply \
         ; do 

    IDX=${i%,*};
    FUNC=${i#*,};
    echo $IDX-$FUNC;

    docker run -v $PWD:$PWD --rm -i ligolang/ligo:0.35.0 compile expression pascaligo --michelson-format json --init-file $PWD/contracts/main/yToken.ligo "SetTokenAction(record index = ${IDX}n; func = Bytes.pack(${FUNC}); end)" > $PWD/$DIR/${IDX}-${FUNC}.json
done



