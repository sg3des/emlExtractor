#!/usr/bin/perl
use MIME::Base64;
use IO::File;
use Fcntl qw(:flock);
use Encode;
use Encode qw(:all);
use Encode::Byte;


use Term::ANSIColor;
use MIME::QuotedPrint::Perl;
use File::Basename;
no warnings 'layer';

my $folder;

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
	foreach $part (split /$boundary/, $buf){
		$step++;
		if($step==1){header($part);next;}
		if($part =~ m/(text\/plain)/mgi){mailText($part,'text'); next;}
		if($part =~ m/(text\/html)/mgi){mailText($part,'html'); next;}
		if($part =~ m/(attachment)/mgi){attachment($part); next;}
	}
}


sub header
{
	my($part) = @_;
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
	@part = cropContent($part);
	@content = content(@part[0]);

	$part = absoluteDecode(@part[1],@content);
	if($type eq 'html'){$part =~ s/@content[0]/utf-8/gi;}
	$filename = $type.".".$type;
	saveFile($filename,$part);
}

sub attachment
{
	my($part) = @_;

	@part = cropContent($part);
	@content = content(@part[0]);
	$header = @part[0];
	$filename = ($header =~ m/.*name="(.*)".*/sgi)[0];
	$filename = string_decode($filename);
	$filename =~ s/[\r\n]//g;
	if($filename !~ m/\./){
		$ext = (@part[0] =~ m/^Content-Type:.*\/(.*);/mgi)[0];
		$filename.=".".$ext;
	}
	if(@content){$part = absoluteDecode(@part[1],@content);}
	else{$part = @part[1];}
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
		# print $charset." ".$encoding."\n";
	if($encoding=~ m/base64/i){$part=decode_base64($part);}
	if($encoding=~ m/quoted-printable/i){$part=decode_qp($part); }
	if($charset && $charset!~m/utf/i){$part=decode($charset,$part);}
	return $part;
}

sub getBoundary
{
	my($buf) = @_;
	@boundary = ($buf =~ m/[\t\s]+boundary="(.*)"/gi);

	foreach $boundary(@boundary){
		$boundary="--".quotemeta($boundary);
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
	$content = substr($part,0,$cropLength+$plus);  #плюс нужен изза разновидности переноса строк 
	substr($part,0,$cropLength+$plus)='';
	return ($content,$part);
}

sub string_decode
{
	my ($string) = @_;
	$string =~ s/from:|to:|subject:|cc://gi;
	$string =~ s/^\s//g;
	$email = '';

	@string = split /[\r\n]/,$string;
	foreach $line (@string){
		$encoding='';$charset='';
		if($line =~ m/@/){
			$email = ($line =~ m/.*(<.*>).*/gi)[0];
			$line =~ s/$email//;
		}
		if($line =~ m/\?/){
		@line = ($line =~ m/.*\=\?(.*)\?(.)\?(.*)\?\=.*/gi);
			$charset = @line[0];
			$encoding = @line[1];
			$line = @line[2];
		}
		if($encoding eq 'B'){$line=decode_base64($line);}
		if($encoding eq 'Q'){$line=decode_qp($line);}
		if($charset){$line = decode($charset,$line);}
		
		if($email){$line = $line." ".$email;}
	}
	return join "\n",@string;
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
