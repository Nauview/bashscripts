#! /bin/bash
echo "What is your name"
read name
if [ $name ]; then
	echo "$name sounds like a tough guy"
else
	echo "Oops! that's not a name ho"

fi
