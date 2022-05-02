#!/bin/sh

for IP in `cat ./ip.txt`
do
  printf "$IP\t"
        LOOKUP_RES=`nslookup $IP`
        FAIL_COUNT=`echo $LOOKUP_RES | grep "** server can't find " | wc -l`;
        if [ $FAIL_COUNT -eq 1 ]
        then
                NAME='Bad FQDNS\n';
        else
                NAME=`echo $LOOKUP_RES | grep -v nameserver | cut -f 2 | grep name | cut -f 2 -d "=" | sed 's/ //'`;
        fi
        echo $NAME
done
