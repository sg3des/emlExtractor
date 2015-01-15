#!/usr/bin/perl
use MIME::Base64;
use IO::File;
use Fcntl qw(:flock);
use Encode;
use Encode qw(:all);
use Encode::Byte;
use Encode::CN;
use Encode::JP;
use Encode::KR;
use Encode::TW;


use Term::ANSIColor;
use MIME::QuotedPrint::Perl;
use File::Basename;
no warnings 'layer';

my $folder;
my $contentNameByEml = 0;
my $emlFilename;
my $overwrite = 0;

my @childs;

$help = "
USAGE: 

/path/to/emlExtractor [option] filename.eml [[option] filename.eml [option] filename.eml ...]

You can unpack multiple EML files in one line, just write them separated by a space.
For each file eml, will be created directory kind filename_eml with same path, where will be unpacked files.

You may set output directory with option:
  -o  --output      set output directory
  -c                set filename for html and text message as the same of filename input eml
  -v  --overwrite   overwrite exists files

set output directory for each file, or one at all, or any other way.

	eml.header - information header of email message
	*.text  - text message in plain text format
	*.html  - text message in html format

";


if(!@ARGV){print $help;}
if(@ARGV[0]=~/--help|-h|\?/){print $help; exit;}

my $arguments = 0;
foreach $filePath(@ARGV){
	# print " - ".$filePath." -";
	if($filePath=~/--help|-h|\?/){print $help; next;}
	if($filePath=~/-o|--output/)          {$folder = @ARGV[$arguments+1]; mkdir $folder; next;}
	if($filePath=~/-c/){$contentNameByEml = 1; next;}
	if($filePath=~/-v|--overwrite/){$overwrite = 1; next;}
	if($filePath){openEml($filePath);}
	$arguments++;
}

sub openEml
{
	my($path) = @_;
	if(!$folder){
		$folder = $path;
		$folder =~ s/\.eml/_eml/i;
		mkdir $folder;
	}

	$emlFilename = basename($path);
	$emlFilename =~ s/\..*//i;
	

	print color 'bold green';	
	print "\n  input:  $path\n";
	print "  output: $folder\n\n";
	print color 'reset';
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
	my $step=0;
	# print $boundary."\n";
	foreach $part (split /$boundary/i, $buf){
		# print $part."\n";
		$step++;
		if($step==1){header($part);  next;}
		if($part =~ m/(text\/plain)/mgi){mailText($part,'text'); next;}
		if($part =~ m/(text\/html)/mgi){mailText($part,'html'); next;}
		if($part =~ m/(filename)/mgi){attachment($part); next;}
		if($part =~ m/(attachment)/mgi){attachment($part); next;}
		if($part =~ m/(description)/mgi){attachment($part); next;}
		if($part =~ m/(name)/mgi){attachment($part); next;}
	}

}

sub header
{
	my($part) = @_;
	# print($part);
	$header .= "From: ".headerField($part,'from')."\n";
	$header .= "To: ".headerField($part,'to')."\n";
	$header .= "CC: ".headerField($part,'cc')."\n";
	$header .= "Subject: ".headerField($part,'subject')."\n";
	$header .= "Date: ".headerField($part,'date')."\n";
	saveFile('eml.header',$header);
	return;
}

sub mailText
{
	my($part,$type) = @_;
	# print $part."\n";
	my @part = cropContent($part);
	my @content = content(@part[0]);
	my $part = absoluteDecode(@part[1],@content);

	if($type eq 'html'){$part =~ s/@content[0]/utf-8/gi;}
	my $filename = $type.".".$type;

	if($contentNameByEml){$filename = $emlFilename.".".$type;}
	saveFile($filename,$part);
}

sub attachment
{
	my($part) = @_;
	my @part = cropContent($part);
	my @content = content(@part[0]);
	if(@content){$text = absoluteDecode(@part[1],@content);}
	else{$text = @part[1];}
	saveFile(@content[2],$text);
	return;
}

sub stringCollect
{
	my($part2,$type) = @_;
	@part = split /[\r\n]/g, $part2;
	$field='';
	_FOR: for (my $num = 0; $num <= $#part; $num++) {
		if($str = (@part[$num] =~ m/$type/mi)[0]){
			$field .= string_decode($str);
			if(@part[$num] =~ m/;$/m){return $field;}
			_WHILE: while(){
				$num++;
				if(@part[$num]){
					if(@part[$num] =~ m/^\t|^\s/mi){

						$field .= string_decode(@part[$num]);
					}else{last _WHILE;}
				}
				if($num>=$#part){last _WHILE;} 
			}
		}
	}
	return $field;
}

sub content
{
	my($part) = @_;
	my $charset = stringCollect($part,'charset="?([a-zA-Z0-9\-]*)"?');
	my $encoding = stringCollect($part,'encoding:\s?(.*)');
	my $filename = stringCollect($part,'filename="?([\w\s\.\,\=\?\-\]\[\`\(\)\'\%\@]*)"?');
	if(!$filename){$filename = stringCollect($part,'name="?([\w\s\.\,\=\?\-\]\[\`\(\)\'\%\@]*)"?');}
	if($ilename !~ m/\.[\w]?$/i){
		$extension = stringCollect($part, 'content-type:\s?[\w]*\/([\w]*);?\s?');
		$filename = $filename.'.'.$extension;
	}
	return ($charset,$encoding,$filename);
}

sub absoluteDecode
{
	my($part,@content) = @_;
	my $charset = @content[0];
	my $encoding = @content[1];
	if($encoding=~ m/base64/i){$part=decode_base64($part);}
	if($encoding=~ m/quoted-printable/i){$part=decode_qp($part);}
	if($charset && $charset!~m/utf/i){$part=decode($charset,$part);}
	return $part;
}

sub getBoundary
{
	my($buf) = @_;
	@boundary = ($buf =~ m/[\t\s]+boundary="(.*)"/gi);

	foreach $boundary(@boundary){
		$boundary="--".quotemeta($boundary)."";
	}
	$boundary = join '|',@boundary;
	if(!$boundary){return;}
	return $boundary;
}


sub cropContent
{
	my($part) = @_;

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
		
	my $content = substr($part,0,$cropLength+$plus);  #плюс нужен изза разновидности переноса строк 

	substr($part,0,$cropLength+$plus)='';
	return ($content,$part);
}

sub string_decode
{
	my ($string) = @_;
	$string =~ s/from:|to:|subject:|cc://gi;
	$email = '';

	@string = split /[\r\n]/,$string;
	foreach $line (@string){
		$str_encoding='';$str_charset='';
		if($line =~ m/@/){
			$email = ($line =~ m/.*(<.*>).*/gi)[0];
			$line =~ s/$email//;
		}
		if($line =~ m/\?/){
		@line = ($line =~ m/.*\=\?(.*)\?(.)\?(.*)\?\=.*/gi);
			$str_charset = @line[0];
			$str_encoding = @line[1];
			$line = @line[2];
		}
		if($str_encoding eq 'B'){$line=decode_base64($line);}
		if($str_encoding eq 'Q'){$line=decode_qp($line);}
		if($str_charset){$line = decode($str_charset,$line);}
		
		if($email){$line = $line." ".$email;}
		$line =~ s/^\s*|\s*$|\r*|\n*|\t//g;
		# print "   > ".$line."\n";
	}
	return join "",@string;
}

sub headerField
{
	my($part,$type)=@_;
	@part = split /[\r\n]/g, $part;
	$field='';
	for (my $num = 0; $num < $#part; $num++) {
		if(@part[$num] =~ /^$type:/mgi){
			$field .= string_decode(@part[$num])."\n";
			# print $field."\n";
			# next;
			_WHILE: while(){
				$num++;
				if(@part[$num]){
					if(@part[$num] =~ m/^\t|^\s/mgi){

						$field .= string_decode(@part[$num])."\n";
					}else{last _WHILE;}
				}
				if($num>=$#part){last _WHILE;} 
			}
		}
	}

	$field =~ s/\n/;/g;
	$field =~ s/;$//g;
	return $field;
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

my $stepOverwriteFilename;

sub saveFile{
	my ($filename,$document) = @_;

	my $filename = lc $filename;
	my $suffix = '';
	if(grep(/^$filename/, @childs)){
		if(!$suffix){$suffix = 1;}
		else{$suffix++;}
	}


	$filename = $suffix.$filename;

	
	if(!$overwrite){$filename = getFilename($filename);}
	my $sfh = new IO::File ">"."$folder/$filename" or die "Cannot open $filename : $!";
	flock($sfh,LOCK_EX);
	binmode($sfh);
	print $sfh $document or die "Write to $filename failed: $!";
	close($sfh) or die "Error closing $filename : $!";

	print $filename."\n";
	push(@childs,$filename);

	return '$filename OK';
}

sub getFilename{
	my ($filename) = @_;
	$stepFilename = '';
	while (-e "$folder/$stepFilename$filename") {
		if($stepFilename==''){$stepFilename=0;}
		$stepFilename++;
	}
	return $stepFilename.$filename;
}

print "\n";