#!/bin/bash 

echo "Checking for sudo executions"
echo "============================="
sleep 2
echo "sudo executions found:"
echo ""
sudo tail -n 10 -f /var/log/secure | egrep "(pam_unix)" | awx '{ print $}


