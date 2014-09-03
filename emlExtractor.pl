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
	# if(length($filePath)<=1){return;}
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
		$boundary = getBoundary($buf);

		if(!$boundary){$boundary = 'Content-Type:';}
		explode($buf,$boundary);
	}
	print "\n";
}

sub explode
{
	my($buf, $boundary) = @_;
	$step=0;
	
	foreach $part (split $boundary, $buf){
		$step++;
		# print $part;
		if($step==1){header($part);next;}
		if($part =~ m/(^Content\-Type.*text\/plain;)/mgi){mailText($part,'text'); next;}
		if($part =~ m/(^Content\-Type.*text\/html;)/mgi){mailText($part,'html'); next;}
		if($part =~ m/(^Content\-Disposition.*attachment;)/mgi){attachment($part); next;}

		# if($part =~ m/^Content-Disposition:attachment;/mgi){attachment($part); next;}
		# if($part =~ m/^Content-Type:text\/plain;/mgi){mailText($part,'text'); next;}
		# if($part =~ m/^Content-Type:text\/html;/mgi){mailText($part,'html'); next;}
	}
}

sub header
{
	my($part) = @_;
	$header .= (($part =~ m/(^from:.*$)/mgi)[0])."\n";
	$header .= (($part =~ m/(^to:.*$)/mgi)[0])."\n";
	$header .= (($part =~ m/(^subject:.*$)/mgi)[0])."\n";
	$header .= (($part =~ m/(^cc:.*$)/mgi)[0])."\n";
	saveFile('eml.header',$header);
	return;
}
sub mailText
{
	my($part,$type) = @_;
	# @content = content($part);
	@part = cropContent($part);
	@content = content(@part[0]);


	$part = absoluteDecode(@part[1],@content);
	if($type eq 'html'){$part =~ s/@content[0]/utf-8/gi;}
	$filename = $type.".".$type;
	# print $filename;
	saveFile($filename,$part);
}

sub attachment
{
	my($part) = @_;
	@part = cropContent($part);
	@content = content(@part[0]);
	$filename = (@part[0] =~ m/filename="(.*)"/gi)[0];
	$filename = string_decode($filename);

	if($filename !~ m/\./){
		$ext = (@part[0] =~ m/^Content-Type:.*\/(.*);/mgi)[0];
		$filename.=".".$ext;
	}

	if(@content){$part = absoluteDecode(@part[1],@content);}
	saveFile($filename,$part);
	
	return;
}
sub content
{
	my($part) = @_;
	$charset = ($part =~ m/charset="(.*)"/mgi)[0];
	$encoding= ($part =~ m/^Content-Transfer-Encoding:(.*)$/mgi)[0];
	return ($charset,$encoding);
}
sub absoluteDecode
{
	my($part,@content) = @_;
	$charset = @content[0];
	$encoding = @content[1];

	if($encoding=~ m/base64/i){$part=decode_base64($part);}
	if($encoding=~ m/quoted-printable/i){$part=decode_qp($part);}
	if($charset){$part=decode($charset,$part);}

	return $part;
}

sub getBoundary
{
	my($buf) = @_;
	$boundary = ($buf =~ m/\t+boundary="(.*)"/i)[0];
	if(!$boundary){return;}
	$boundary = "--".substr($boundary,0,10); #берем только первые 10 симоволов, это нужно потому что бывает несколько баундарев и обычно различаются они где-то не в начале.
	return $boundary;
}


sub cropContent
{
	my($part) = @_;

	# print $part;
	# $crop = index($part,"eJ8");
	# if($crop+1){substr($part,0,$crop)='';}

	if(index($part,"\r")+1){$delimter="\r"; $plus=1;}else{$delimter="\n";$plus=0;}


	my $num=0;
	my $cropLength=0;
	my $startSchDelimter=0;
	_CROP:	
	foreach my $line (split $delimter, $part){
		$num++;
		$length = length($line)+1;
		$cropLength += $length;
		if($line =~ /charset/i){$startSchDelimter = 1;}
		if($line =~ /encoding/i){$startSchDelimter = 1;}
		if($startSchDelimter>0 && $length <= 2){
			$cropLine=$num; 
			last _CROP;
		}
	}
	# print $cropLength."\n";
	$content = substr($part,0,$cropLength+$plus);  #плюс нужен изза разновидности переноса строк 
	substr($part,0,$cropLength+$plus)='';


	return ($content,$part);


	# $crop = index($part,$delimter,$startCrop);

	# print $startCrop." ".$crop."\n";
	# $part =~ s/(^Content.*$)|(^\t.*$)//mgi; # убираем все строки которые начинаются со слова Content или с таба скорее всего это заголовок
	# $part =~ s/\r$\r$|^\n^\n//mgi; #убираем двойные переносы строк

	# return $part;
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
		$string =~ s/[^\w\.\s\=\?\+\-\/]//gi; #убираем непечатные символы
		$string =~ s/\=\?+$charset|\?B\?|\?\=//gi;
		if($quoted eq 'base64'){$string=decode_base64($string);}
		if($quoted eq 'qp'){$string=decode_qp($string);}
		if($charset){$string = decode($charset,$string);}
	}
	if($email){$string = $string." ".$email;}
	return $string;
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

sub saveFile{
	my ($filename,$document) = @_;

	$folder =~ s/\.eml/_eml/gi;
	mkdir $folder;

	my $sfh = new IO::File ">"."$folder/$filename" or die "Cannot open $filename : $!";
	flock($sfh,LOCK_EX);
	binmode($sfh);
	print $sfh $document or die "Write to $filename failed: $!";
	close($sfh) or die "Error closing $filename : $!";

	print $filename."\n";
	return '$filename OK';
}
