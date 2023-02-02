<?php

// Generate a list of 256 randomly ordered integers.

$numbers = [];
for ($i=0; $i<255; $i++) {
	$numbers[$i] = $i;
}

for ($i=(count($numbers)-1); $i > 0; $i--) {
	$rand = random_int(0, $i);
	$temp = $numbers[$rand];
	$numbers[$rand] = $numbers[$i];
	$numbers[$i] = $temp;
} 

echo "\t\tdc.w\t" . implode(',',$numbers) ."\n";
