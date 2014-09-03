#!/usr/bin/perl
use MIME::Base64;
use IO::File;
use Fcntl qw(:flock);
use Encode; # qw(decode encode);
use Encode qw(:all);

use Encode::Byte;
use Encode::CN;
use Encode::JP;
use Encode::KR;
use Encode::TW;

use Term::ANSIColor;
use MIME::QuotedPrint::Perl;
use File::Basename;
# use Text::Iconv;
# use Convert::Cyrillic;
no warnings 'layer';

my $folder;
my $delimter;
my $charset;

# my $TextIncov;

print "\n";
foreach $filePath(@ARGV){
	openEml($filePath);
}


sub openEml
{
	my($path) = @_;
	$folder = $path;
	print color 'bold green';	print $path."\n";	print color 'reset';
	
	my $fh = new IO::File "< $path" or die "Cannot open $path : $!";
	flock($fh,LOCK_SH);
	binmode($fh);
	my $buf;
	my $buflen = (stat($fh))[7];

	while (read($fh,$buf,$buflen)) {
		$delimter = searchDelimter($buf);



		$boundary = getBoundary($buf);
		if(length($boundary)>1){explode($buf,$boundary);}
		else{explode($buf,'Content-Type:');}

		# header($buf);
	}
	print "\n";
}


sub explode
{
	my($buf, $boundary) = @_;
	$step=0;
	foreach $part (split $boundary, $buf){
		$step++;
		# if($step >= 2){$cropHeader=$part;}
		my $filename='',$type='',$textType='';$headerSearch=0;
		foreach $line (split $delimter, $part){

			if($line =~ /filename/)			{$filename = $line;}
			if($line =~ /binary/)				{$type = 'binary';}
			if($line =~ /base64/)				{$type = 'base64';}
			if($line =~ /msword/)				{$ext = 'doc';}
			if($line =~ /text\/plain/)	{$textType = 'text';}
			if($line =~ /text\/html/)		{$textType = 'html';}

			if($line =~ /koi8-r/i)			{$charset = 'koi8-r';}
			if($line =~ /utf-8/i)				{$charset = 'utf-8';}
			if($line =~ /windows-1251/i){$charset = 'windows-1251';}

			if($line =~ /from:/i){$headerSearch+=1;}
			if($line =~ /to:/i){$headerSearch+=1;}
			if($line =~ /subject:/i){$headerSearch+=1;}
			if($line =~ /date:/i){$headerSearch+=1;}
		}
		if (length($filename)>1 && length($type)>1){
			attachment($part,$filename,$type,$ext);
		}
		if(length($textType)>1){
			print "body.".$textType."\n";
			mailText($part,$textType);
		}
		if($headerSearch>2 && $step<=2){
			header($part);
		}
	}
	# if($cropHeader){}
}

sub header
{
	my($partHeader) = @_;
	my %header;
	foreach my $line (split m/\r|\n/, $partHeader){
		if($line =~ m/^From:/i && $line =~ m/@/){$header{'from'}=$line;}
		if($line =~ m/^To:/i  && $line =~ m/@/)	{$header{'to'}=$line;}
		if($line =~ m/^Subject:/i)							{$header{'subject'}=$line;}
		if($line =~ m/^Date:/i)									{$header{'date'}=$line;}
	}

	foreach $k (keys %header){
		@replace = ('From: ','To: ','Subject: ','Date: ');
		foreach $replace (@replace){
			$header{$k} = str_replace($replace,'',$header{$k});
		}
		$header{$k} = string_decode($header{$k});
		%result = (%result,$k.": ".$header{$k}."\n");
	}
	$header = join("",%result);
	if($header){
		saveFile('eml.header',$header);
		print "eml.header\n";
	}
	return;
}

sub string_decode
{
	my ($string) = @_;
	my @result = ();
	$email = '';

	if($string =~ m/@/){
		@email = ($string =~ m/(\<+[\w]+\@+[\w]+\.+[\w]+\>)/);
		$email = join '',@email;
		$string =~ s/$email//;
	}

	if($string =~ /windows-1251/) {$charset = 'windows-1251';}
	if($string =~ /koi8-r/) {$charset = 'koi8-r';}

	if($string =~ m/$charset/){
		if($string =~ m/\?B\?/){$quoted = 'base64';}
		if($string =~ m/\?Q\?/){$quoted = 'qp';}
		# print "   ".$string."\n";
			$string =~ s/[^\w\.\s\=\?\+\-\/]//gi; #убираем непечатные символы
		

		$string =~ s/\=\?+$charset|\?B\?|\?\=//gi;
		

		if($quoted eq 'base64'){$string=decode_base64($string);}
		if($quoted eq 'qp'){$string=decode_qp($string);}
		if($charset){$string = decode($charset,$string);}
		# $string = from_to($string, $charset, 'utf-8');
		# $string = $TextIconv->convert($string);
		# print " > ".$string." ".$charset." ".$quoted."\n";
	}
	$string = $string." ".$email;
	return $string;
}


sub mailText{
	my($part, $type) = @_;


	foreach my $line (split m/\r|\n/, $part){
		if($line =~ m/base64/i){$quoted = 'base64';}
		if($line =~ m/quoted/i){$quoted = 'qp';}
		if($line =~ m/utf-8/i){$charset = 'utf-8';}
		if($line =~ m/windows-1251/i){$charset = 'windows-1251';}
		if($line =~ m/koi8-r/i){$charset = 'koi8-r';}
	}




	$part = cropGarbage($part,$delimter);

	# print $part;	



	@part = split($delimter,$part);pop @part;$part = join("",@part); #delete last line!


	
	if($quoted eq 'base64'){$part = decode_base64($part);}
	if($quoted eq 'qp'){$part = decode_qp($part);}
	if($charset){$part = decode($charset,$part);}


	# $part = from_to($part, $charset, 'utf-8');
	# $part = $TextIconv->convert($part);

	# $testString = '1tPRINHu6ujw/+3o';
	# $testString = decode_base64($testString);
	# print decode($charset,$testString)."\n";
	# print $test = ($TextIncov->convert($testString))."\n";
	# print Convert::Cyrillic::cstocs('windows-1251', 'UTF8', $testString)."\n";
	# print $part."\n";
	if($type eq 'html' && $charset){$part = str_replace($charset,'utf-8',$part);}

	$filename = $type.".".$type;
	saveFile($filename,$part);
	
}

sub attachment
{
	my($document, $filename, $type, $ext) = @_;

	$filename = string_decode($filename);
	# print "   ".$filename." ".$ext."\n";
	# if($filename =~ /koi8-r/) {$fn_charset = 'koi8-r'; $filename = str_replace('=?koi8-r','',$filename);}
	# if($filename =~ /windows-1251/) {$fn_charset = 'windows-1251'; $filename = str_replace('=?windows-1251','',$filename);}

	# if($filename =~ /\?B\?/) {$fn_quoted = 'base64'; $filename = str_replace('?B?','',$filename);}
	# if($filename =~ /\?Q\?/) {$fn_quoted = 'qp'; $filename = str_replace('?Q?','',$filename);}
	
	# 	@filename = ($filename =~ m/(\"+\w*+[.]*+\w*+\")/); #m/(\"+[\w]+\.+[\w]+\")/
	# 	$filename = join '',@filename;
	# 	$filename =~ s/"//g;
	# 	$filename = str_replace('?=','',$filename);
	# # $filename = str_replace('filename=','',$filename);

	# # $filename = str_replace('"','',$filename);
	# # $filename	=~ s/^\s+|\s+$//g;
	# # $filename = str_replace(' ','_',$filename);

	# $filename	=~ s/\r|\n//g;
	# # $filename =~ s/[\)\(\"\'\?]|filename|//gi;
	# if($fn_quoted eq 'base64'){$filename=decode_base64($filename);}
	# if($fn_quoted eq 'qp'){$filename=decode_qp($filename);}
	# if($fn_charset){$filename = decode($fn_charset,$filename);}


	# $filename =~ s/[^\w\.\r ]//gi; #убираем непечатные символы

	# if($filename !~ m/\./){$filename = $filename.".".$ext;}

	$document = cropGarbage($document,$delimter);

	# substr($document,-5)='';
	# $document = substr($document,201,-1);
	# print $document;
	# print "   ".$type;
	if($type eq 'base64'){
		# $document = MIME::Base64::decode($document);
		# $document =~ s/\r|\n//g;
		$document = decode_base64($document);
	}
	print "$document\n";
	saveFile($filename,$document);

	# open(my $fh, '>', 'winmail.dat');
	# print $fh $document;
	# close $fh;


	# if($filename =~ /.dat/){
	# 	$exec = 'tnef --overwrite '.$filename;
	# 	exec $exec;
	# }
	return;
}

sub searchDelimter
{
	my($document) = @_;
	@delimters = ("\r","\n");  # todo: add type of delimters;
	foreach $delimter(@delimters){
		$index = index($document,$delimter);
		if($index+1) {return $delimter;}
	}
	
}

sub search
{
	my ($text,$what,$index) = @_;
	return index($text,$what,$index);
}


sub getBoundary
{
	my($buf) = @_;
	_BOUNDARY:
	foreach my $line (split m/\n+/, $buf){
		if($line =~ /boundary/) {
			$boundary=$line; 
			last _BOUNDARY;
		}
	}
	if(!$boundary){print "boundary not found\n"; return;}
	$boundary = str_replace('boundary="','',$boundary);
	chop $boundary;
	@boundary = split(/-|_|=|"|\s/, $boundary);
	_BOUNDARY:
	foreach my $partBoundary (@boundary){
		if($partBoundary) {
			return $partBoundary;
			last _BOUNDARY;
		}
	}
}

sub cropGarbage
{
	my($part,$delimter) = @_;

	my $num=0;
	my $cropLength=0;
	my $startSchDelimter=0;
	_CROP:	
	foreach my $line (split $delimter, $part){
		$num++;
		$length = length($line)+1;
		$cropLength += $length;
		if($line =~ /charset/){$startSchDelimter = 1;}
		if($startSchDelimter>0 && $length <= 2){
			$cropLine=$num; 
			last _CROP;
		}
	}
	
	if($delimter eq "\r"){$plus = 1;}else{$plus=0;} #плюс нужен изза разновидности переноса строк 
	substr($part,0,$cropLength+$plus)='';

	return $part;
}

my $fileNum=0;
sub saveFile{
	my ($filename,$document) = @_;
	

	$folder = str_replace('.eml','_eml',$folder);
	mkdir $folder;

	my $sfh = new IO::File ">"."$folder/$filename" or die "Cannot open $filename : $!";
	flock($sfh,LOCK_EX);
	binmode($sfh);
	print $sfh $document or die "Write to $filename failed: $!";
	close($sfh) or die "Error closing $filename : $!";
	return '$filename OK';
}




sub str_replace
{
	my $replace_this = shift;
	my $with_this  = shift; 
	my $string   = shift;
	
	my $length = length($string);
	my $target = length($replace_this);
	
	for(my $i=0; $i<$length - $target + 1; $i++) {
		if(substr($string,$i,$target) eq $replace_this) {
			$string = substr($string,0,$i) . $with_this . substr($string,$i+$target);
			# return $string; #Comment this if you what a global replace
		}
	}
	return $string;
}
