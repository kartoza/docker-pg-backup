#!/bin/bash

# Function to setup config file for using s3 functions
function s3_config() {

  if [[ ! -f /settings/s3cfg ]]; then
    echo "/settings/s3cfg doesn't exists"
    # If it doesn't exists, copy from /config directory if exists
    if [[ -f /config/s3cfg ]]; then
      cp -f /config/s3cfg /root/.s3cfg
    else
      # default value
      envsubst < /settings/s3cfg.default > /root/.s3cfg
    fi
  fi

}

# Cleanup S3 bucket
function clean_s3bucket() {
  S3_BUCKET=$1
  DEL_DAYS=$2
  s3cmd ls s3://${S3_BUCKET} --recursive | while read -r line; do
    createDate=$(echo $line | awk {'print ${S3_BUCKET}" "${DEL_DAYS}'})
    createDate=$(date -d"$createDate" +%s)
    olderThan=$(date -d"-${S3_BUCKET}" +%s)
    if [[ $createDate -lt $olderThan ]]; then
      fileName=$(echo $line | awk {'print $4'})
      echo $fileName
      if [[ $fileName != "" ]]; then
        s3cmd del "$fileName"
      fi
    fi
  done
}

