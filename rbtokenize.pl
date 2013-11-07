#!/usr/local/bin/perl -w

# This software is freely available for research, education and evaluation.
# Please read the license terms http://www.linguistics.ruhr-uni-bochum.de/~dipper/licence.txt, before you download the software! By downloading the software, you agree to the terms stated there.

# Stefanie Dipper
# dipper AT linguistics DOT rub DOT de

# CHANGE LOG:

# 2009 May 14
# - ordinals: no longer allowed in sentence-final position
# - added special treatment for multiple word-final special characters
#   (don't trigger sentence boundaries as usually)
# - bug fix: added final dollar $wordchar =~ m/$reg$/
#   (otherwise 'Industrie.' is not tokenized properly...)

# 2008 Sep 5
# - added special treatment for '...'
# - added "[IVX]+." as ordinals
#   and "[MDLIVX]+" as cardinals
# - replaced [a-z] by [a-zäöüß]

# VERSION: 0.1  (2008, Sep 4)
 
use strict;
use locale;
use Getopt::Long;

# TODO: abbreviated date expressions like Do. Jan.
# TODO: add more date expressions

# reads in plain text + list of abbreviations 
# and produces tokenized version. Output formats:
#
# 1. text format: 
# - tokens separated by space
# - 1 sentence/line
# - paragraph boundaries indicated by empty line
#
# 2. xml format: like text, but uses tags such as <tok>, <sent_bound/>, etc.

# NOTES:
# - simple linebreaks are ignored!
# - trailing and leadling newlines are ignored
#   multiple newlines are squeezed

# TYPES:
# for words: 
# - unmarked default: [a-zA-Z]+
# - "alphanum", if word contais digits (among other characters)
# - "mixed", if word contains characters like brackets, quotes, ...
# - "allCap", if word consists of capitalized characters only
#
# for numbers:
# - "card": cardinals
# - "ord":  ordinals
# - "year"
#
# for abbreviations:
# - "abbrev", with subtypes:
#   . source='listed'  (i.e. full abbreviation is listed in file <abbrev>)
#   . source='regEx'   (i.e. matching regex is listed in file <abbrev>)
#   . source='nextWordLC' (i.e. next word is lower case)
#
# for special charcters:
# - "specialChar_lead":  special chars preceding a word (like "(")
# - "specialChar_trail": special chars following a word (like ")")
# - "punc":              punctuation marks
#
# for whitespace:
# - unmarked default: single space
# - "tab": tabulator
# - "carrRet": carriage return
# - "unknown": anything else
# NOTE: multiple types are possible (e.g. type="space,tab")


#  TODO: different types of abbrev files
#1. "clear" abbrevs, e.g. "ca."     
#   -> cannnot be final word in a sentence
#2. "ambiguous" abbrevs, e.g. "Str." 
#   -> punct mark might have double function: abbrev + sentence marker
#      hence, check for following word: upcase or lower case?
#  TODO: make year recognizers work with -s (space) option

##############################################
# command-line options, standard-values
##############################################

my $xmlIn=0; my $xmlOut=0; my $printSpace=0; my $printType=0;
my $file_abbrev="/dev/null";

# yearRobust: if this option is chosen, any four-digit ordinal starting with 1 or 2
# will be interpreted as year followed by sentence-final punctuation mark.
# If the option is NOT chosen, then the preceding context of the ordinal is checked
# carefully (for expressions like 'Januar' or 'Winter' or 'Jahr')
my $yearRobust=0;

my $yearRegex="(Jan|J(ä|ae)nner|Feb|M(ae|ä)rz|Apr|Mai|Jun|Jul|Aug|Sep|Okt|Nov|Dez|Jahre?n?|Winter|Fr(ü|ue)(ling|jahr)|Sommer|Herbst)";

# not used currently
my $XMLname="[a-zA-Z\\d_\.:-]+";
my $XMLval="(?:\"|\')[^>\"]+(?:\"|\')";
my $XMLattr="$XMLname=$XMLval";

GetOptions('z|xmlIn' => \$xmlIn,
	   'x|xmlOut' => \$xmlOut,
	   's|space' => \$printSpace,
	   't|type' => \$printType,
           'a|abbrev=s' => \$file_abbrev,
	   'y|yearRobust' => \$yearRobust );

unless (scalar @ARGV == 2) {
    die "

USAGE:
perl tokenize.perl [OPTIONS] <fileIn.text> <fileOut.tok>

OPTIONS:
[-a|-abbrev <abbrev>]
\t\t<abbrev> is a file with a list of abbreviations
\t\tlist format: one abbreviation per line (like \"etc.\")
\t\tabbreviations can consist of regular expressions: \"/regex/\"
\t\t(e.g. \"/str./\")

[-z|-xmlIn]\tdon't parse XML tags or entities

[-x|-xmlOut]\ttriggers xml output

[-s|-space]
\tincludes spaces in output (implies -xml)
\t\tNOTE: simple linebreaks are ignored, multiple empty lines
\t\tare squeezed (and interpreted as paragraph boundaires),
\t\tleading and trailing empty lines are deleted

[-t|-type]
\tincludes information about space/word types (implies -xml)
\t\tunmarked default: words = [a-zA-Z]+; spaces = \"\\ +\"

[-y|-yearRobust]
triggers a simplified version of date tagging
\t\t(see script for more details)

NOTE: 
The script contains a hard-wired list of German date expressions\n\n";
}

if ($printSpace != 0) { $xmlOut=1; }
if ($printType != 0) { $xmlOut=1; }

my $text = shift @ARGV;
my $out = shift @ARGV;


##############################################
# function for replacing special characters in XML mode
##############################################

sub replace {
    my $word = shift;

    if ($xmlOut) { 
	$word =~ s/&/&amp;/g;
	$word =~ s/</&lt;/g;
	$word =~ s/>/&gt;/g;
	$word =~ s/\"/&quot;/g;
	$word =~ s/\'/&apos;/g;
    }

    return($word);
}

##############################################
# function to empty buffer (operating on global vars...)
##############################################

my (@buffer_tok, @buffer_xml, @buffer_xmlType, $j);

sub empty_buffers {
    # empty buffers (filled by for-loop)
    while ( $#buffer_tok >= 0 ) {

	# don't use replace-function here
	# because some of the buffer entries already contain XML markup!
	$j = pop @buffer_tok; print TOK $j;
	$j = pop @buffer_xml; print XML $j;
	$j = pop @buffer_xmlType; print XMLtype $j;
    }
}

##############################################
# function for recognizing year numbers
##############################################

sub rec_years {
    my $word = shift;  # $text[$i]
    my $pred = shift;  # $text[$i-1]
    my $prepred = shift; # $text[$i-2]

    # for-digit numbers: 1988, 2007: special treatment
    # 1st version: it's always year + ".", regardless of context
    if ( $word =~ m/^(1|2)[0-9][0-9][0-9]$/ && $yearRobust == 1) {
	return 1;
    }
    
    elsif ( $word =~ m/^(1|2)[0-9][0-9][0-9]$/ && $yearRobust == 0) { 
	# 2nd version: carefully check for preceding context
	# Jan 2007. or 1.1.1990.  -> sentence boundary
	if  ( $pred =~ m/^$yearRegex/ 
	      || ( $pred =~ m/^(0?[1-9]|10|11|12)\.$/    # 03.
		   && $prepred =~ m/^(0?[1-9]|[1-3][1-9])\.$/  # 31.
		   )
	      ) { 
	    return 1;
	}
	else { return 0; }
    }
}


##############################################
# Main program
##############################################


##############################################
# 1. read in list of abbreviations
##############################################

open (ABBREV,"$file_abbrev") or die ("$!");
my (%abbrev, %abbrev_reg);

while (<ABBREV>) {
    chomp $_;
    # skip empty lines
    if ($_ =~ m/^\s*$/) { next; }
    # delete leading/trailing whitespace
    $_ =~ s/^\s*(.+)\s*$/$1/;
    # abbreviations can be regular expressions, marked by /.../
    if ( $_ =~ /\/(.+)\// ) { $abbrev_reg{$1} = 1; }
    else { $abbrev{$_} = 1; }
}
close (ABBREV) or die ("$!");



##############################################
# 2. tokenize
##############################################

my $tok_out; my $xml_out; my $xmlType_out;
$tok_out="/dev/null"; 
$xml_out="/dev/null"; 
$xmlType_out="/dev/null"; 

if ($xmlOut == 0) { $tok_out=$out; }
elsif ($printType != 0) { $xmlType_out=$out; }
else { $xml_out=$out; }

open (IN,"$text") or die ("$!");
open (TOK,">$tok_out") or die ("$!");
open (XML,">$xml_out") or die ("$!");
open (XMLtype,">$xmlType_out") or die ("$!");

my (@text, $line, $word, $char, $wordchar, $reg, $i);
my $abbrev="type='abbrev'";
my @type; my $type;
my $empty_line=0; my $start=0;

print XML "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
print XML "<text>\n";
print XMLtype "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
print XMLtype "<text>\n";


##############################################
while (<IN>) {
##############################################

    @text=();
    $line = $_;
    chomp $line;

    ######################################
    # 0a. empty lines
    if ($line =~ m/^\s*$/) { 
	unless ($start) { next; } # ignore leading empty lines 

	# else: collect original empty lines
	#+ squeeze multiple empty lines
	#+ delete trailing empty lines
	$empty_line=1;
	next;
    }

    ######################################
    # 0b. non-empty lines
    else { $start=1; }

    if ( $empty_line ) {
	# preceding line(s) have been empty -> print out now
	print TOK "\n";
	print XML "<newline/>\n";
	print XMLtype "<space type=\"newline\">\n</space>\n";
	$empty_line=0;
    }

    # hack: hide spaces within XML tags/attributes so that these are not split
    if ( $xmlIn && $line =~ m/<[^>]+>/ ) {
	while ($line =~ m/(<[^>]+\s+[^>]*>)/) {
	    my $left = $`; my $right = $';
            my $tag = $1; $tag =~ s/ /xxxSPACExxx/g;
            $line = "$left$tag$right";
	}
    }

    ######################################
    # 1. splitting the input
    ######################################

    if ($printSpace == 0) { 
	# simple split: splits $line on whitespace and returns list
	@text = split(' ',$line);
    }

    else {
	# "full" split: record info about whitespace
	while ($line) {
	    # \w: [0-9a-zA-Z_]
	    # \s: [\ \t\r\n\f]
	    # \S: [^\s]
	    # The period '.' matches any character but "\n"

	    # no whitespace:
	    if ($line =~ m/^(\S+)(.*)/) {
		$line =~ s/^(\S+)(.*)/$2/;
		push @text, $1; 
	    }
	    
	    # whitespace:
	    elsif ($line =~ m/^(\s+)(.*)/) {
		$line =~ s/^(\s+)(.*)/$2/;
		push @text, $1;
	    }
	}
    }


  WORD: for $i ( 00..$#text ) {

      $word=$text[$i];
      $type="";

      if ( $xmlIn && $word =~ m/xxxSPACExxx/ ) {
	  # since we do not analyse '<' or '>'
	  # this should cause no harm here
	  $word =~ s/xxxSPACExxx/ /g;
      }

      ######################################
      # 2. cut off leading " or (
      ######################################

     while ( $word =~ m/^([\(\"\'\`])(.+)$/ ) { 
	  print TOK "$1 ";
	  print XML " <tok$type>" . replace($1) . "</tok>\n";
	  print XMLtype " <tok type='specialChar_lead'>" . replace($1) . "</tok>\n";
	  $word=$2;
      }
      
      ######################################
      # 3. cut off trailing special characters
      ######################################

      # XML/HTML entities: don't analyze internally
      if ( $xmlIn && $word =~ m/^\&([a-zA-Z]+|\#\d+);$/) {
	  print TOK "$word ";
	  print XML " <tok>$word</tok>\n";
	  print XMLtype " <tok type='entity'>$word</tok>\n";
	  empty_buffers(); next WORD;   
      }

      while ( $word =~ m/^(.+)([\)\"\'\`\.:\?!;,])$/ ) {
	  $word=$1;
	  $char=$2;
   
	  # -----------------------------------------------
	  # 3a. special case: word ends with "."
	  # -----------------------------------------------
	  #    - if word is recognized as abbreviation, nothing more to be done
	  #      i.e. we can safely leave for-loop (by 'next WORD')
	  #    - else: cut off "." and work on remaining word
	  #      (may contain further special characters)
	  if ($char eq ".") {
	      $wordchar="$word$char";
	      # check whether word is abbreviation
	  
	      # (i) it's listed in %abbrev -> abbrev
	      if ( exists($abbrev{$wordchar}) ) { 
		  print TOK "$wordchar ";
		  print XML " <tok>" . replace($wordchar) . "</tok>\n";
		  print XMLtype " <tok $abbrev source='listed'>" . replace($wordchar) . "</tok>\n";
		  empty_buffers(); next WORD; 
	      }

	      # (ii) it's listed in %abbrev_reg -> abbrev
	      else { 
		  for $reg ( keys %abbrev_reg ) {
		      if ( $wordchar =~ m/$reg$/ ) { 
			  print TOK "$wordchar "; 
			  print XML " <tok>" . replace($wordchar) . "</tok>\n";
			  print XMLtype " <tok $abbrev source='regEx'>" . replace($wordchar) . "</tok>\n";
			  empty_buffers(); next WORD; 
		      }
		  }
	      }
	      
	      # (iii) if $wordchar = *... -> treat ... as one unit
	      # however, check following word for upper case,
	      # if yes insert sentence boundary
	      if ($wordchar =~ m/^(.*?)(\.\.\.\.*)$/) {
		  $word = $1;
		  $char = $2;

		  if ( exists($text[$i+1]) 
		       && $text[$i+1] =~ m/^[A-ZÄÖÜ]/ ) { 
		      push @buffer_tok, "$char\n";
		      push @buffer_xml, " <tok>" . replace($char) . "</tok>\n<sent_bound/>\n";
		      push @buffer_xmlType, " <tok type='punc'>" . replace($char) . "</tok>\n<sent_bound/>\n";
		  }
		  else {
		      push @buffer_tok, "$char ";
		      push @buffer_xml, " <tok>" . replace($char) . "</tok>\n";
		      push @buffer_xmlType, " <tok type='punc'>" . replace($char) . "</tok>\n";
		  }
		  # $char shouldn't be used any more
		  $char = ""; $wordchar="$word";
	      }

	      # (iv) following word is in lower case -> abbrev
	      # (and we don't check for further special characters)
	      elsif ( exists($text[$i+1]) 
		   && $text[$i+1] =~ m/^[a-zäöüß]/ ) { 
		  print TOK "$wordchar "; 
		  print XML " <tok>" . replace($wordchar) . "</tok>\n";	
		  print XMLtype " <tok $abbrev source='nextWordLC'>" . replace($wordchar) . "</tok>\n";	
		  empty_buffers(); next WORD; 
	      }
	      

	      # -----------------------------------------------
	      # 3b. if word is a number, then usually interpret it as ordinal
	      # -----------------------------------------------
	      if ( $word =~ m/^[0-9]+$/
		   || $word =~ m/^[IVX]+$/) {

		  unless ( exists($text[$i-1]) ) { $text[$i-1] = "EMPTY"; }
		  unless ( exists($text[$i-2]) ) { $text[$i-2] = "EMPTY"; }
		  
		  # sole exceptions:
		  # (i) if word occurs sentence final (e.g. 'Artikel 4.')
		  # (ii) if date expression (of form 'month year.' or 
		  #      'ord ord year.') is recognized, then split 
		  #      year and "."
		  if ( $i == $#text  ||
		      rec_years($word,$text[$i-1],$text[$i-2])
		      ) {
		      # sentence-final or date successfully recognized
		      print TOK "$word $char\n"; 
		      print XML " <tok>" . replace($word) . "</tok>\n";	
		      print XML " <tok>" . replace($char) . "</tok>\n<sent_bound/>\n";	
		      print XMLtype " <tok type='year'>" . replace($word) . "</tok>\n";	
		      print XMLtype " <tok type='punct'>" . replace($char) . "</tok>\n<sent_bound/>\n";	
		  }
		  else {
		      # else: ordinal -> one token only, no sentence boundary
		      print TOK "$wordchar "; 
		      print XML " <tok>" . replace($wordchar) . "</tok>\n";
		      print XMLtype " <tok type='ord'>" . replace($wordchar) . "</tok>\n";
		  }
		  
		  empty_buffers(); next WORD; 
	      }
	  } # end of: if ($char eq ".")
	  

	  # -----------------------------------------------
	  # 3c. characters marking sentence boundary
	  # -----------------------------------------------
	  # (don't use 'elsif' here because non-abbreviational "."
	  # is handled here as well)

	  if ($char =~ m/^[\.:\?!;]$/) { 

	      # if after the period etc. there are quotation marks and
	      # more sentence-final punctuations, include these
	      # into the current sentence

	      # (i) easy case first: current character ist the last one 
	      #     within the word (and, hence, [-1] does not exist)
	      # (ii) or next-to-easy case: previous character [-1] is not special
	      if (! exists($buffer_tok[-1]) ||
		  ( exists($buffer_tok[-1]) && 
		    $buffer_tok[-1] !~ m/^[\.:\?!;\"\']\s$/
		    )
		  ) {
		  # insert sentence boundary
		  push @buffer_tok, "$char\n";
		  push @buffer_xml, " <tok>" . replace($char) . "</tok>\n<sent_bound/>\n";
		  push @buffer_xmlType, " <tok type='punc'>" . replace($char) . "</tok>\n<sent_bound/>\n";
	      }

	      else {
		  # (iii) difficult case: sequence of special characters
		  # 2 cases:
		  # a. final character of the word is a quote 
		  #    -> include them into the current sentence
		  #       (i.e. add boundary behind them)
		  # b. final character is period, question mark etc.
		  #    -> don't insert sentence boundaries for word-middle chars

		  # case a.
		  if ( $buffer_tok[0] =~ m/^[\"\']\s$/ ) {
		      $buffer_tok[0] .= "\n";
		      $buffer_xml[0] .= "<sent_bound/>\n";
		      $buffer_xmlType[0] .= "<sent_bound/>\n";
		  }
		  # case b. -> nothing to do
		      
		  push @buffer_tok, "$char ";
		  push @buffer_xml, " <tok>" . replace($char) . "</tok>\n";
		  push @buffer_xmlType, " <tok type='punc'>" . replace($char) . "</tok>\n";
	      }
	  }

	  # -----------------------------------------------
	  # 3d. commas
	  # -----------------------------------------------

	  elsif ($char eq ",") { 
	      push @buffer_tok, "$char ";
	      push @buffer_xml, " <tok>" . replace($char) . "</tok>\n";
	      push @buffer_xmlType, " <tok type='punc'>" . replace($char) . "</tok>\n";
	  }

	  # -----------------------------------------------
	  # 3e. other trailing special characters
	  # -----------------------------------------------

	  else {
	      push @buffer_tok, "$char ";
	      push @buffer_xml, " <tok>" . replace($char) . "</tok>\n";
	      push @buffer_xmlType, " <tok type='specialChar_trail'>" . replace($char) . "</tok>\n";
	  }
      }  # end of: while $word ends with special character


      ######################################
      # 4. space
      ######################################

      if ($word =~ m/^\s+$/) {
	  if ($printSpace == 0) { next; }
	  else {
	      if ($printType) {
		  @type=(); $type="";
		  # include info about spaces (only with XML output)
		  # \s: [\ \t\r\n\f]
		  if ($word eq " ") { 1; }
		  elsif ($word =~ m/\ /) { push @type, "space"; }
		  if ($word =~ m/\t/) { push @type, "tab"; }
		  if ($word =~ m/\r/) { push @type, "carrRet,"; }
		  if ($word !~ m/[\ \t\r]/) { push @type, "unknown"; }
		  
		  for $i ( 00..$#type ) { 
		      $type .= "$type[$i]"; 
		      if ($i<$#type) { $type .= ",";}
		  }
		  if ($type ne "") { $type = " type='$type'"; }
		  print XMLtype " <space$type>" . replace($word) . "</space>\n"; 
	      }
	      else { print XML " <space>" . replace($word) . "</space>\n"; }
	  }
      }

      ######################################
      # 5. cardinals
      ######################################


      elsif ( $word =~ m/^[0-9]+$/
	      || $word =~ m/^[MDLIVX]+$/ ) {

	  unless ( exists($text[$i-1]) ) { $text[$i-1] = "EMPTY"; }
	  unless ( exists($text[$i-2]) ) { $text[$i-2] = "EMPTY"; }

	  if (rec_years($word,$text[$i-1],$text[$i-2])) {
	      # year successfully recognized
	      print TOK "$word "; 
	      print XML " <tok>" . replace($word) . "</tok>\n";	
	      print XMLtype " <tok type='year'>" . replace($word) . "</tok>\n";	
	  }
	  else {
	      # else: cardinal
	      print TOK "$word "; 
	      print XML " <tok>" . replace($word) . "</tok>\n";
	      print XMLtype " <tok type='card'>" . replace($word) . "</tok>\n";
	  }
      }

      ######################################
      # 6. ordinary word, no trailing special characters
      ######################################

      else {
	  print TOK "$word "; 
	  
	  if ($printType) {
	      @type=(); $type="";
	      if ($word =~ m/\d/) { push @type, "alphanum"; }
	      if ($word =~ m/[\(\)\{\}\[\]\"\'\`\.:\?!;,\/]/) { push @type, "mixed"; }
	      if ($word =~ m/^[A-ZÄÖÜ]+$/) {  push @type, "allCap"; }
	      
	      for $i ( 00..$#type ) { 
		  $type .= "$type[$i]"; 
		  if ($i<$#type) { $type .= ",";}
	      }
	      if ($type ne "") { $type = " type='$type'"; }
	      print XMLtype " <tok$type>" . replace($word) . "</tok>\n"; 
	  }

	  else { print XML " <tok>" . replace($word) . "</tok>\n"; }
      }

      empty_buffers();

  } # end of for-loop on individual word
}

print XML "</text>\n";
print XMLtype "</text>\n";

close (IN) or die ("$!");
close (TOK) or die ("$!");
close (XML) or die ("$!");
close (XMLtype) or die ("$!");


exit 0;
