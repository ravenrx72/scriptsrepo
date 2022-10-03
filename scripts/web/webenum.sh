#!/bin/#!/usr/bin/env bash

url=$1

if [ ! -d "$url" ];then
    mkdir $url
fi

if [! -d "$url/recon" ]; then
    mkdir $url/recon
fi

echo "Harvest subdomains with assetfinder.."
assetfinder $url >> $url/recon/assets.text
cat $url/recon/assets.txt | grep $1 >> $url/recon/final.txt
rm  $url/recon/assets.text
