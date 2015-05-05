use bigint;

$cnt = 0;
$byte_cnt = 0;
$OutFile = "NULL";
$buffer;

@pts_byte_arr = (0, 0, 0, 0, 0);
@pts_modified_byte_arr = (0, 0, 0, 0, 0);

$pts = 0;
$pts_previous = 0;
$pts_modified = 0;
$pts_modified_previous = 0;
# $divideby = 30;
# $divideby = 4434709321;

$num_args = $#ARGV + 1;
if ($num_args != 4) {
	print "Error: Usage: perl modify_pts.pl file_name pts_pid(in decimal) ADD_nSUB(1:add, 0:sub) ADD_nSUB_val(to be added/subtracted to PTS @ 90kHz)\n";
	print "        eg.   perl modify_pts.pl example.ts 256 1 4500\n";
	print "                          -> This adds 50msec(4500/90000) to all PTS's of PID = 256\n";
	exit;
}

$File = $ARGV[0];
$pts_pid = $ARGV[1];
$operation = $ARGV[2];
$add_val = $ARGV[3];

$pts_pid_upper = $pts_pid >> 8;
$pts_pid_lower = $pts_pid & 0xFF;

print "\n	$pts_pid_upper, $pts_pid_lower\n";

print "	Processing $File\n";
		
open(INFILE, " < $File") or die("Error: cannot open file '$File'\n");
  	
$OutFile = "modify_pts_report.txt";
	
open(OUTFILE, " > $OutFile") or die("Error: cannot open file '$OutFile'\n");
  	
binmode INFILE;

$TSOutFile = $File . ".out";
open(TSOUTFILE, " > $TSOutFile") or die("Error: cannot open file '$TSOutFile'\n");
binmode TSOUTFILE;
  	
print OUTFILE "Hex_Indenx 	  PTS Bytes 	      PTS Value 	    PTS Diff    Modified PTS   Modif_TS_Diff   Modif_PTS_Bytes\n";
print OUTFILE "-----------------------------------------------------------------------------------------------------------\n";
	
while ( read (INFILE, $buffer, 1)) {
	
	print (TSOUTFILE $buffer);
	 
	if (ord($buffer) == 0x47) {
	 	
		#print "\n$cnt, 0x47 found";
	 	$cnt = $cnt + 1;
	 		
	 	#if ($cnt == 1000) { 
		# 	goto END 
		#};
	 	
		$pts = 0;
	 	$adapfieldlength = 0;
	 	$adapfieldlengthtotal = 0;
	 		
	 	read (INFILE, $buffer, 1); print (TSOUTFILE $buffer);
	 	$pid_upper_temp = ord($buffer);
	 		
	 	$pid_upper = $pid_upper_temp & 0x1F;
	 		
	 	read (INFILE, $buffer, 1); print (TSOUTFILE $buffer);
	 	$pid_lower = ord($buffer);
	 		
	 	if (($pid_upper == $pts_pid_upper) and ($pid_lower == $pts_pid_lower) and (($pid_upper_temp & 0x40) == 0x40)) { 
	 		#printf ("%d %d, ", $pid_upper, $pid_lower);
	 		#print "byte cnt: $byte_cnt\n";
	 		
	 		#print "PID and Start Indicator found\n";	
	 		read (INFILE, $buffer, 1); print (TSOUTFILE $buffer);
	 		$byte4th = ord($buffer);
	 		$adap_cntrl = $byte4th & 0x30;
	 		
	 		if (($adap_cntrl == 0x20) or ($adap_cntrl == 0x30)) {
	 		
		 		#print "Adaptation Field found\n";
		 		
		 		# Adaptation field length
	 			read (INFILE, $buffer, 1); print (TSOUTFILE $buffer);
	 			$adapfieldlength = ord($buffer);
	 				 			
	 			read (INFILE, $buffer, $adapfieldlength); print (TSOUTFILE $buffer);
	 			
	 			$adapfieldlengthtotal = $adapfieldlength + 1;

			} 
				
			read (INFILE, $buffer, 6); print (TSOUTFILE $buffer);
			read (INFILE, $buffer, 1); print (TSOUTFILE $buffer);
				
			# 7 Flags
			read (INFILE, $buffer, 1); print (TSOUTFILE $buffer);
			$flags_7 = ord($buffer) & 0xC0;
				
			if (($flags_7 == 0x80) or ($flags_7 == 0xC0)) {
				
				#print "PTS found\n";	
				
				# PES header data length
				read (INFILE, $buffer, 1); print (TSOUTFILE $buffer);

				printf (OUTFILE "%8x >> ", $byte_cnt);
				
				# PTS
				for ($i = 0; $i < 5; $i++) {
  					read (INFILE, $pts_byte_arr[$i], 1);
  					printf (OUTFILE "%3x", ord($pts_byte_arr[$i]));
				}

				$pts = (ord($pts_byte_arr[0]) & 0x0E) << 29;
				$pts = $pts | (ord($pts_byte_arr[1]) << 22);				
				$pts = $pts | ((ord($pts_byte_arr[2]) & 0xFE) << 14);
				$pts = $pts | (ord($pts_byte_arr[3]) << 7);
				$pts = $pts | ((ord($pts_byte_arr[4]) & 0xFE) >> 1);
				
				# $pts_modified = $pts / $divideby;
        if($operation == 1) {
          $pts_modified = $pts + $add_val;
        } else {
          $pts_modified = $pts - $add_val;
        }
				
				$pts_modified_byte_arr[0] = (($pts_modified & 0x01C0000000) >> 29) | 0x21;
				$pts_modified_byte_arr[1] =  ($pts_modified & 0x003FC00000) >> 22;
				$pts_modified_byte_arr[2] = (($pts_modified & 0x00003F8000) >> 14) | 0x01;
				$pts_modified_byte_arr[3] =  ($pts_modified & 0x0000007F80) >> 7;
				$pts_modified_byte_arr[4] = (($pts_modified & 0x000000007F) << 1) | 0x01;
				
				
				printf (OUTFILE "%15u", $pts);
				printf (OUTFILE "%15u", ($pts - $pts_previous));
				printf (OUTFILE "%15u", $pts_modified);
				printf (OUTFILE "%15u", ($pts_modified - $pts_modified_previous));

				printf (OUTFILE "\t\t");
				
				for ($i = 0; $i < 5; $i++) {
  					printf (OUTFILE "%3x", $pts_modified_byte_arr[$i]);
				}
				
				#for ($i = 0; $i < 5; $i++) {
  				#	if (ord($pts_byte_arr[$i]) != $pts_modified_byte_arr[$i]) {
  				#		print "Mismatch\n";
				#	}
				#}
				
				for ($i = 0; $i < 5; $i++) {
					print (TSOUTFILE chr($pts_modified_byte_arr[$i]));
				}
				printf (OUTFILE "\n");
				
				$pts_previous = $pts;
				$pts_modified_previous = $pts_modified;
				
			} else {
				read (INFILE, $buffer, 6); print (TSOUTFILE $buffer);
			}
			
			read (INFILE, $buffer, (188 - 3 - $adapfieldlengthtotal - 15)); print (TSOUTFILE $buffer);
				
  		} else {
	  		
	 		read (INFILE, $buffer, (188 - 3)); print (TSOUTFILE $buffer);
	 		
		}
  		
	 	$byte_cnt = $byte_cnt + 188;
	 		
	} else {
		print "\nError: not 0x47";
	}
};
  
END:
	
close INFILE or die("Error: cannot close file '$File'\n");
close OUTFILE or die("Error: cannot close file '$OutFile'\n");
close TSOUTFILE or die("Error: cannot clos