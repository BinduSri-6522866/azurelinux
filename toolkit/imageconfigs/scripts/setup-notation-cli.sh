#!/bin/bash

set -ex

sudo tar xzf /root/notation-cli/notation_1.2.0_linux_amd64.tar.gz -C /root/notation-cli
sudo mv /root/notation-cli/notation /usr/bin
sudo curl -o /etc/verifiers/ca.crt 'https://www.microsoft.com/pkiops/certs/Microsoft%20Supply%20Chain%20RSA%20Root%20CA%202022.crt'
sudo notation cert add --type ca --store supplychain /etc/verifiers/ca.crt
sudo notation policy import /etc/verifiers/trustpolicy.json

