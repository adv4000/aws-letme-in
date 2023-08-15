#!/bin/bash
#-------------------------------------------------------------------------------
# If your Public IP frequently changes and you need to keep your SecurityGroup
# open ONLY to your Public IP, just execute script again, it will update
# SecurityGroup Rule with a new Public IP. Can be used by multiply IAM users.
#
# Version   Date             Name             Info
# 1.0       15-Aug-202      Denis Astahov     Initial Version
#
#-------------------------------------------------------------------------------
SG_AWS_REGION="us-west-2"                  # Region where  SecurityGroup exist
SG_AWS_ACCOUNT_ID="827611452653"           # Account where SecurityGroup exist
SG_ID_TO_UPDATE="sg-0739261d2996c0005"     # SecurityGroup ID to Update
SG_FR_PORT=8080                            # Open FROM port number
SG_TO_PORT=8080                            # Open TO   port number
GET_PUBLICIP_URL="checkip.amazonaws.com"   # URL which response with your PublicIP

get_public_ip(){
  echo -n "Getting your Public IP Address... "
  CURRENT_PUBLIC_IP=$(curl --silent $GET_PUBLICIP_URL)
  if [ $? -eq 0 ]; then
     echo "Public IP is: $CURRENT_PUBLIC_IP"
  else
     echo "ERROR getting your Public IP, do you have access to Internet?"
     exit 1
  fi
}

get_aws_user(){
  echo "Checking your AWS User..."
  AWS_STATUS=$(aws sts get-caller-identity)
  if [ $? -eq 0 ]; then
     AWS_ACCOUNT=$(echo $AWS_STATUS | jq .Account -r)
     AWS_USERARN=$(echo $AWS_STATUS | jq .Arn -r)
     AWS_USERNAME=$(echo ${AWS_USERARN#*/})
     echo "  AWS ACCOUNT : $AWS_ACCOUNT"
     echo "  AWS_USERNAME: $AWS_USERNAME"
     if [ $AWS_ACCOUNT != $SG_AWS_ACCOUNT_ID ]; then
       echo "Your AWS Credentials configured to the wrong AWS account: $AWS_ACCOUNT, it's NOT $SG_AWS_ACCOUNT_ID !!!"
       exit 1
     fi
  else
     echo "ERROR Accessing AWS, have you configured your AWS Credentials?"
     exit 1
  fi
}

check_securitygroup_rule(){
  SECURITYGROUP_RULE=$(aws ec2 describe-security-group-rules \
    --filters Name="group-id",Values=$SG_ID_TO_UPDATE \
              Name="tag:Name",Values="IAMUser:$AWS_USERNAME" \
    --region $SG_AWS_REGION)
  RULE_ID=$(echo $SECURITYGROUP_RULE | jq .SecurityGroupRules[0].SecurityGroupRuleId -r)
  RULE_IP=$(echo $SECURITYGROUP_RULE | jq .SecurityGroupRules[0].CidrIpv4 -r)

  if [ "$RULE_IP" = "$CURRENT_PUBLIC_IP/32" ]; then
    echo "Your Public IP: $CURRENT_PUBLIC_IP already whitelisted for Server!"
    exit 0
  else
    if [ "$RULE_ID" = "null" ]; then
      echo "No Rule Found for your username, adding new rule..."
      add_securitygroup_rule
    else
      echo "Old Rule found for your username, deleteing old and adding new..."
      delete_securitygroup_rule
      add_securitygroup_rule
   fi
  fi
}

delete_securitygroup_rule(){
  echo -n "Deleting Rule for IP: $RULE_IP -> "
  DELETE_STATUS=$(aws ec2 revoke-security-group-ingress \
         --group-id $SG_ID_TO_UPDATE \
         --security-group-rule-ids $RULE_ID \
         --region $SG_AWS_REGION)
  if [ $? -eq 0 ]; then
     echo "Deleted Sucessfully!"
  else
     echo "ERROR Deleting old rule!"
     exit 1
  fi
}

add_securitygroup_rule(){
  echo -n "Adding Rule for IP: $CURRENT_PUBLIC_IP/32 -> "
  ADD_STATUS=$(aws ec2 authorize-security-group-ingress \
      --group-id $SG_ID_TO_UPDATE \
      --ip-permissions "IpProtocol=tcp,FromPort=$SG_FR_PORT,ToPort=$SG_TO_PORT,IpRanges=[{CidrIp=$CURRENT_PUBLIC_IP/32,Description='Managed By Script'}]" \
      --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=IAMUser:$AWS_USERNAME}]" \
      --region $SG_AWS_REGION)
  if [ $? -eq 0 ]; then
     echo "Added Sucessfully, try access Server!"
  else
     echo "ERROR Adding new rule!"
     exit 1
  fi
}

#--------Script Start Here---------------------
get_public_ip
get_aws_user
check_securitygroup_rule
#--------Script End Here-----------------------
