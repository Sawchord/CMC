#!/bin/bash
openssl ecparam -name secp160r1 -genkey -out ec-priv.pem 
openssl ec -in ec-priv.pem -pubout -text
rm ec-priv.pem