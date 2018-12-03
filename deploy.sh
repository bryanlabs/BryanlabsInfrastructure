#!/bin/bash

# Customise the application deployment by modifying the variabels below.
set -x

APPNAME="bryanlabs" #must be lowercase alphaonly.
S3BUCKET="bryanlabs"
S3PUBLICBUCKET="bryanlabs-public"
S3PREFIX="iac"
EC2KEYPAIRNAME="BRYANLABS-AWS"
SimpleADPW='changeme'

# Dynamic Vars, Don't change these.
FILENAME="$APPNAME.zip"
SEEDURL="https://s3.amazonaws.com/$S3PUBLICBUCKET/$FILENAME"
PIPELINEBUCKET="$(aws s3 ls | grep "$APPNAME-pipe" | cut -d ' ' -f3)"
export APPNAME S3BUCKET S3PREFIX EC2KEYPAIRNAME FILENAME SEEDURL PIPELINEBUCKET

  # Start CLean.
  [[ -f $FILENAME ]] && rm $FILENAME
  [[ -f buildspec.yml ]] && rm buildspec.yml

# Copy Templates to aws folder.

for TEMPLATE in $(find templates/ -type f -name "*.template")
do
  aws cloudformation package --template-file $TEMPLATE --s3-bucket $S3PUBLICBUCKET --output-template-file $TEMPLATE
  NEWNAME="$(echo $TEMPLATE | sed 's/^templates\///g' | sed 's/.template//g')"
  cp $TEMPLATE cfts/$NEWNAME.cft
done

# Modify templates in aws folder.
for TEMPLATE in $(find cfts/ -type f -name "*.cft")
do
  sed -i "s/__S3BUCKET/$S3BUCKET/g" $TEMPLATE
  sed -i "s/__S3PUBLICBUCKET/$S3PUBLICBUCKET/g" $TEMPLATE
  sed -i "s/__S3PREFIX/$S3PREFIX/g" $TEMPLATE
  sed -i "s/__FILENAME/$FILENAME/g" $TEMPLATE

done

# Modify buildspec.
cp templates/buildspec.yml buildspec.yml
sed -i "s/__S3BUCKET/$S3BUCKET/g" buildspec.yml
sed -i "s/__S3PUBLICBUCKET/$S3PUBLICBUCKET/g" buildspec.yml
sed -i "s/__S3PREFIX/$S3PREFIX/g" buildspec.yml

# The application specific pipeline bucket must not exist when deploying the app. Delete stack will not clean up S3. This will warn if a manuel delete is needed.

__STACK="$(aws cloudformation describe-stacks --stack-name $APPNAME)"
export __STACK

if [[ "${#PIPELINEBUCKET}" -gt 0 ]] && [[ ! -n "$__STACK" ]]
then
  echo "$PIPELINEBUCKET"
  echo "Error: Found a previous S3 bucket for Application: s3://$PIPELINEBUCKET. Delete via console, or choose a new APPNAME."
else
  echo "Deploying Application: $APPNAME"


  # Ensure buckets in place.
  aws s3api create-bucket --bucket $S3BUCKET
  aws s3api create-bucket --bucket $S3PUBLICBUCKET --acl public-read
  

  # Move cloudformation templates, and reposource archive to S3.
  aws s3 sync cfts/ s3://$S3PUBLICBUCKET/$S3PREFIX/ --acl public-read

  # Archive everything and upload to S3. This archive will be the base for the seedrepo.
  git add .
  git commit -m "Updated Repo with dynamic changes."
  zip -r $FILENAME . 
  aws s3 cp $FILENAME s3://$S3PUBLICBUCKET/ --acl public-read

  # Clean up again.
  # Start CLean.
  [[ -f $FILENAME ]] && rm $FILENAME
  [[ -f buildspec.yml ]] && rm buildspec.yml
  
# Deploy the Application.
  echo "Please wait while the application deploys, Status can be seen from cloudformation console."
  aws cloudformation deploy --template-file stack.yml --stack-name $APPNAME \
  --role-arn arn:aws:iam::601953533983:role/Bryanlabs-Cloudformation-servicerole --capabilities CAPABILITY_NAMED_IAM --parameter-overrides \
  TemplateBucket=$S3PUBLICBUCKET/$S3PREFIX \
  EC2KeyPairName=$EC2KEYPAIRNAME \
  SimpleADPW=$SimpleADPW \
  SeedURL=$SEEDURL
fi

CICDSTACK=$(aws cloudformation describe-stacks --stack-name $APPNAME | jq .Stacks[].Outputs | jq -r '.[] |select(.OutputKey=="CICDStackName").OutputValue')
SSHCloneURL=$(aws cloudformation describe-stacks --stack-name $CICDSTACK | jq .Stacks[].Outputs | jq -r '.[] | select(.OutputKey=="SSHCloneURL") | .OutputValue')

echo "#############################"
echo "Customise your Infrastructure"
echo "#############################"
echo ""
echo "SSHCloneURL: $SSHCloneURL"
echo ""
echo "Clone your new repo, modify templates, and commit your changes."
