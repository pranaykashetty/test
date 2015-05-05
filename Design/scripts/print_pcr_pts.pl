#-------------------------------------------------------------------------------
# $Project$
# $Header$
#
# This file contains confidential and proprietary information.
# (C) Copyright - Coreel Technologies, Bangalore.
#
# Project   : AVDM_V2
# File      : print_pcr_pts.pl
# Author    : Dilraj
# Version   : 0.2
# Date      : 20-Sep-13
# Status    : Initial
# Abstract  : 
#
# Modification History
#-------------------------------------------------------------------------------
#  Date      |By      |Version |Change Description
#-------------------------------------------------------------------------------
#  xx-xxx-xx |Dilraj  |0.01    |Intitial
#  20-Sep-13 |Dilraj  |0.02    |Fixed adaptation length zero condition
#  17-Oct-13 |Dilraj  |0.03    |Fixed decode time calc if PTS and PCR both are 
#                              |present in a TS packet
#-------------------------------------------------------------------------------

use Cwd;
use File::Basename;

$cnt = 0;
$byte_cnt = 0;
$ReportFile = "NULL";
$buffer;

@pts_byte_arr = (0, 0, 0, 0, 0);
@pcr_byte_arr = (0, 0, 0, 0, 0);

$pcr_pkt_cnt = 0;
$old_pcr_value = 0;
$old_pts_value = 0;
$ts_pkt_cnt = 0;

$pcr_at_pts = 0.0;
$pcr_pts_diff = 0.0;
$decode_time = 0.0;

#-------------------------------------------------------------------------------
# 
#-------------------------------------------------------------------------------
$num_args = $#ARGV + 1;
if ($num_args != 4) {
  print "Error: Usage: print_pcr_pts.pl ts_file_name pcr_pid pts_pid bit_rate\n";
  print "            e.g. print_pcr_pts.pl example.ts 256 256 9000000\n";
  exit;
}

$File = $ARGV[0];
$pcr_pid = $ARGV[1];
$pts_pid = $ARGV[2];
$bit_rate = $ARGV[3];

($f_name, $f_path, $f_suffix ) = fileparse($File, "\.[^.]*");
$dir  = getcwd;

open(TSFILE, " < $File") or die("Error: cannot open file '$File'\n");
binmode TSFILE;

$ReportFile = $f_name."_pcr_pts_report.txt";
open(REPFILE, " > $ReportFile") or die("Error: cannot open file '$ReportFile'\n");

print REPFILE "Current Dir : $dir\n";
print REPFILE "File Name   : $File\n";
print REPFILE "PCR PID     : $pcr_pid\n";
print REPFILE "PTS PID     : $pts_pid\n";
print REPFILE "Bitrate     : $bit_rate\n\n\n";

print REPFILE "---------------------------------------------------------------------------------------------------------------------\n";
print REPFILE "Hex_index  |    PCR_value   |   PCR_diff (in msec)   |    PTS_value   |     PTS_diff (in msec) |  Decode Time in msec\n";
print REPFILE "---------------------------------------------------------------------------------------------------------------------\n";
#print REPFILE "--------------------------------------------------------------------------------\n";
#print REPFILE "Hex_index  |    pcr_value   |    pcr_diff    |    pts_value   |     pts_diff    \n";
#print REPFILE "--------------------------------------------------------------------------------\n";

while (read (TSFILE, $buffer, 1)) { #TS:sync_byte 
  if (ord($buffer) == 0x47) {
    # $ts_pkt_cnt++;
    $ts_pkt_cnt = tell (TSFILE) - 1;
    $print_pcr_val = 0;
    $print_pts_val = 0;
    
    read (TSFILE, $buffer, 1);  #TS:PID[12:8] 
    $rd_byte_cnt = 2;
    $pld_strt_indc = (ord($buffer)) & 0x40;
    $pid = ((ord($buffer)) & 0x1F) << 8;
    read (TSFILE, $buffer, 1);  #TS:PID[7:0] 
    $rd_byte_cnt++;
    $pid = $pid + (ord($buffer));
    
    if($pid == $pcr_pid) {
      $pcr_pid_match = 1;
    } else {
      $pcr_pid_match = 0;
    }
    
    if(($pid == $pts_pid) and ($pld_strt_indc == 0x40)){
      $pts_pid_match = 1;
    } else {
      $pts_pid_match = 0;
    }
    
    if(($pcr_pid_match == 1) or ($pts_pid_match == 1)) {
      read (TSFILE, $buffer, 1);  #TS:adaptation_field_control 
      $rd_byte_cnt++;
      $adap_cntrl = (ord($buffer)) & 0x30;
      
#-------------------------------------------------------------------------------
# PCR decode
#-------------------------------------------------------------------------------
      if (($adap_cntrl == 0x20) or ($adap_cntrl == 0x30)) {
        read (TSFILE, $buffer, 1);  #TS:adaptation_field_length
        $rd_byte_cnt++;
        $adapfieldlength = ord($buffer);
        
        if($adapfieldlength != 0) {
        
          read (TSFILE, $buffer, 1);  #TS:PCR_flag
          $rd_byte_cnt++;
          $pcr_flag = (ord($buffer)) & 0x10;
          
          if (($pcr_flag == 0x10) and ($pcr_pid_match == 1) ) {
            for ($i = 0; $i < 6; $i++) {
              read (TSFILE, $pcr_byte_arr[$i], 1);  #TS:PCR
              $rd_byte_cnt++;
            }
            $pcr_value = ord($pcr_byte_arr[0]) << 25;
            $pcr_value = $pcr_value | (ord($pcr_byte_arr[1]) << 17);
            $pcr_value = $pcr_value | (ord($pcr_byte_arr[2]) << 9);
            $pcr_value = $pcr_value | (ord($pcr_byte_arr[3]) << 1);
            $pcr_value = $pcr_value | ((ord($pcr_byte_arr[4]) & 0x80) >> 7);
            
            $print_pcr_val = 1;
            $pcr_pkt_cnt = $ts_pkt_cnt;
          } 
          $adapfieldlength = $adapfieldlength + 1;
        }
      } else {
        $adapfieldlength = 0;
        $rem_adapt_len = 0;
      }
      

#-------------------------------------------------------------------------------
#PTS decode
#-------------------------------------------------------------------------------
      if (($adap_cntrl == 0x10) or ($adap_cntrl == 0x30)) {
        read (TSFILE, $buffer, 7); # read out first seven bytes of PES packet
        $rd_byte_cnt = $rd_byte_cnt + 7;
        
        read (TSFILE, $buffer, 1);
        $rd_byte_cnt++;
        $pts_dts_flags = ord($buffer) & 0xC0;
        
        read (TSFILE, $buffer, 1);
        $rd_byte_cnt++;
        
        if (($pts_dts_flags == 0x80) or ($pts_dts_flags == 0xC0)) {
          for ($i = 0; $i < 5; $i++) {
            read (TSFILE, $pts_byte_arr[$i], 1);
            $rd_byte_cnt++;
          }
          $pts_value = (ord($pts_byte_arr[0]) & 0x0E) << 29;
          $pts_value = $pts_value | (ord($pts_byte_arr[1]) << 22);        
          $pts_value = $pts_value | ((ord($pts_byte_arr[2]) & 0xFE) << 14);
          $pts_value = $pts_value | (ord($pts_byte_arr[3]) << 7);
          $pts_value = $pts_value | ((ord($pts_byte_arr[4]) & 0xFE) >> 1);
          
          if ($pts_pid_match == 1) {
            $print_pts_val = 1;
          } 
        }
      }

#-------------------------------------------------------------------------------
# PCR, PTS difference calculation
#-------------------------------------------------------------------------------      
      $pcr_diff = $pcr_value - $old_pcr_value;
      $pcr_diff_time = $pcr_diff/90.0;
      $pts_diff = $pts_value - $old_pts_value;
      $pts_diff_time = $pts_diff/90.0;
    
      if ($print_pcr_val == 1) {
      $old_pcr_value = $pcr_value; #This allows proper PCR-PTS difference calc if TS has both PCR and PTS
      }
      if ($print_pts_val == 1) {
        $old_pts_value = $pts_value;
      }
      # $pcr_at_pts = ($ts_pkt_cnt - $pcr_pkt_cnt) * 188.0 * 8 / $bit_rate * 1000;
      $pcr_at_pts = ($ts_pkt_cnt - $pcr_pkt_cnt) * 8 / $bit_rate * 1000;
      $pcr_pts_diff = ($pts_value - $old_pcr_value)/90.0;
      $decode_time = $pcr_pts_diff - $pcr_at_pts;
      
      if (($print_pcr_val == 1) and ($print_pts_val == 1)) {
        # printf (REPFILE "%09X  |  ", ($ts_pkt_cnt*188));
        printf (REPFILE "%09X  |  ", $ts_pkt_cnt);
        printf (REPFILE "%12u  |  ", $pcr_value);
        printf (REPFILE "%12u(%6.2f)  |  ", $pcr_diff, $pcr_diff_time);
        printf (REPFILE "%12u  |  ", $pts_value);
        printf (REPFILE "%12u(%6.2f)  |  ", $pts_diff, $pts_diff_time);
        printf (REPFILE "%8.3f", $decode_time);
        printf (REPFILE "\n");
        # $old_pcr_value = $pcr_value;
        # $old_pts_value = $pts_value;
      } elsif ($print_pcr_val == 1) {
        # printf (REPFILE "%09X  |  ", ($ts_pkt_cnt*188));
        printf (REPFILE "%09X  |  ", $ts_pkt_cnt);
        printf (REPFILE "%12u  |  ", $pcr_value);
        printf (REPFILE "%12u(%6.2f)  |  ", $pcr_diff, $pcr_diff_time);
        printf (REPFILE "          --  |            --(    --)  |        --");
        printf (REPFILE "\n");
        # $old_pcr_value = $pcr_value;
      } elsif ($print_pts_val == 1) {
        # printf (REPFILE "%09X  |  ", ($ts_pkt_cnt*188));
        printf (REPFILE "%09X  |  ", $ts_pkt_cnt);
        printf (REPFILE "          --  |            --(    --)  |  ");
        printf (REPFILE "%12u  |  ", $pts_value);
        printf (REPFILE "%12u(%6.2f)  |  ", $pts_diff, $pts_diff_time);
        printf (REPFILE "%8.3f", $decode_time);
        printf (REPFILE "\n");
        # $old_pts_value = $pts_value;
      }
    }
    read (TSFILE, $buffer, (188 - $rd_byte_cnt));
    # printf ("\n%d", $ts_pkt_cnt);
  } else {
    print "\nError: not 0x47";
    # printf ("\nError: not 0x47 instead %x", ord($buffer));
  }
};
  
END:

close TSFILE or die("Error: cannot close file '$File'\n");
close REPFILE or die("Error: cannot close file '$ReportFile'\n");
  