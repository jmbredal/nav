#!/usr/bin/perl

# $Id: smsd.pl,v 1.6 2002/09/23 10:58:38 knutvi Exp $
#
# Dette er en sms-demon som henter sms meldinger i fra
# databasen p� bigbud og sender dem ved hjelp av 
# mobiltelefon koblet til com-porten.
#
# Hvis det ligger flere sms i ut k�en som skal til 
# samme person, sendes det kun en sms + antall meldinger
# som ikke sendes.
#
# B�de meldinger som blir sendt og meldinger som ikke sendes
# skrives til logg. 
#
# Det skrives til logg og sendes mail vist vist det oppst�r 
# feil under sendigen av sms'en

# Innparametere som kan brukes er
# -c  / setter alle meldingen i utk�en til ignored
# -d xx / setter tiden mellom hver gang demone sjekker databasen, default er 30 sek
# -t xxxxxxxx / sender en testmelding til telefonnummeret


# Scriptet ble laget 06.01.2001 av 
# Knut-Helge Vindheim
# ITEA Nettgruppen

# Modifisert til � jobbe mot postgreSQL 9/10-01 av
# Gro-Anita Vindheim
# ITEA Nettgruppen

# Modifisert til � kj�re som navcron for NAVRun 18/07-2002 av
# Morten Vold
# ITEA Nettgruppen
 
use POSIX qw(strftime);
use strict;
use vars qw($opt_c $opt_d $opt_t $opt_h);
use Getopt::Std;
use English;
use Pg;


my $vei = "/usr/local/nav/navme/lib";
require "$vei/database.pl";
require "$vei/fil.pl";


my $pidfil = '/usr/local/nav/local/var/run/smsd.pl.pid';
my $conffil= '/usr/local/nav/local/etc/conf/smsd.conf';

justme();				# sjekker om smsd kj�res fra f�r.
switchuser(); # S�rg for at vi kj�rer som brukeren navcron

getopt('dt'); 

my %conf = &hash_conf($conffil);
my $logfil = $conf{logfil} || '/usr/local/nav/local/log/smsd.log';
my %navconf = &read_navconf();
my $MAILDRIFT = $navconf{ADMIN_MAIL};


my $temp;
my $smssyk = 0;

my ($tlf, $tekst, @respons, $respons_, $v, $nr1);
my ($dbh, $ko, $ko2, $maxidsok, $smsid);
my $dato = strftime "Tid: %H:%M:%S", localtime;
my $forsinkelse = 30;


# Viser hjelp
if ($opt_h) {
    print "\nsmsd [-[hc] [-d sec] [-t tlf]\n -h Viser denne hjelpen\n -c Setter alle meldingen i utk�en til ignored\n -d setter sleep i sekunder\n -t sender en testmelding til <tlf>\n\n";
    exit(0);   
}

# Kj�rer en lokal test p� systemet
if ($opt_t) {
    $respons_ = &send_sms($opt_t, "Dette er en test, smsd er n� startet.");
    print "$respons_\n";
    exit(0);    
}


# Lager bare en connection mot databasen, som er konstant. H�per det ikke krasjer alt...
my %dbconf = &db_readconf();
my $dbname = $dbconf{db_trapdetect};
my $dbuser = $dbconf{script_smsd};
my $userpw = $dbconf{'userpw_' . $dbuser};
my $conn = &db_connect($dbname, $dbuser, $userpw);

# Sletter utk�en i databasen
if ($opt_c) {
    
    my $sql = "UPDATE smsutko SET sendt=\'I\' WHERE sendt=\'N\'";
    
    my $ok = &db_execute($conn,$sql);
}


# Sjekker om en �nsker en annen forsinkelse
if ($opt_d) {
    $forsinkelse = $opt_d;
}


# Henter ut antall sms vi har sendt.


my $sql = "SELECT max(smsid) FROM smsutko";

&sjekk_conn;
$maxidsok = &db_select($conn,$sql);

if ($maxidsok->ntuples)
{
    while (my @smsid = $maxidsok->fetchrow)
    {
	$smsid=$smsid[0];
    }
}
else
{
    $smsid=0;
}

my $sql = "SELECT tlf,smsutko.id,melding FROM smsutko,bruker WHERE bruker.id = smsutko.brukerid AND sendt=\'N\'";

# background ourself and go away only if we get this far..
close(STDOUT); # Disconnect from terminal...
my $pid = fork();
if ($pid) {
    # Skriver pid til fil
    open (PIDFIL, ">$pidfil");
    print PIDFIL $pid;
    close (PIDFIL);
    exit(0);
}

$0 = 'smsd.pl: NAV SMS daemon ready...';

# Kj�rer en uendelig l�kke her
while ($v=2) {
    &sjekk_ko;
    sleep $forsinkelse;
}


sub sjekk_ko {
    my (%hash_ko_, @line);
    
    &sjekk_conn;
    my $ko_N = &db_select($conn,$sql);
    
    if ($ko_N->ntuples) {
	while ( @line = $ko_N->fetchrow) {
	    $hash_ko_{$line[0]}{$line[1]} = $line[2];
	}
    }
    
    if (%hash_ko_) {
	&sorter_sms(%hash_ko_);
    }
}




sub sorter_sms {
    my (%hash_ko, %hash_ko2_, $user, $id, @line, $id_);
    my ($nr1_user, $meld_nr) = 1;
    my ($text_, $tlf_, @sendt_id, @ignored_id, $ant_ignored);

    my ($ga,$ok);
    
    (%hash_ko) = @_;
    open(LOGFIL,">>$logfil");
    
    # Bruk 'sort keys' vist en vist en �nsker at lavest mobil-nummer skal komme f�rst 
    foreach $user (sort keys %hash_ko) {

	@sendt_id = ();
	@ignored_id = ();


	# Clear hash for ny bruker
	%hash_ko2_ = (); 

	# Henter p� nytt alle meldingen til denne personen

	$ko = "SELECT smsutko.id,melding FROM smsutko,bruker WHERE bruker.id=smsutko.brukerid AND sendt=\'N\' AND tlf=\'$user\'"; 

	&sjekk_conn;
	$ok = &db_select($conn,$ko);

	# Hvis der var noe flere meldinger legges de i en hash
	if ($ok->ntuples) {
	    while ( @line = $ok->fetchrow) {
		$hash_ko2_{$line[0]} = $line[1];
	    }
	}


	$meld_nr = 1;
	$ant_ignored = 0;
	$text_ = "";

	foreach $id (keys %hash_ko2_) {

	    # Meldinger som sendes til personen
	    if ((length($text_) + length($hash_ko2_{$id})) < 136) {
		if ($meld_nr eq '1') {
		    $text_ = $hash_ko2_{$id};
		}
		elsif ($meld_nr eq '2') {
		    $text_ = "1:".$text_."\\;  2:".$hash_ko2_{$id};
		}
		else {
		    $text_ = $text_."\\; $meld_nr:".$hash_ko2_{$id};
		}

		$tlf_ = $user;
		push @sendt_id, $id; 

		$meld_nr++;
	    }

	    # Meldinger som ignoreres, en teller dem opp
	    else {
		push @ignored_id, $id;
		$ant_ignored++;
	    }

	}

	# Hvis der er flere en 1 melding til persone
	if ($ant_ignored > 0) {
	    $respons_ = &send_sms($tlf_, $text_." +$ant_ignored se web.");
	}

	# Hvis der kun er en melding til personen
	else {
	    $respons_ = &send_sms($tlf_, $text_);
	}


	# Sjekker om sendingen var vellykket
	unless ($respons_) {

	    if ($smssyk) {
		$smssyk = 0;

		# Skriv logg
		$dato = strftime "%d\.%m\.%Y %H:%M:%S", localtime;
		print LOGFIL "\nsmsd_up: $dato\t$respons_\n";

		# Send mail
		open(MAIL, "|mail -s 'RE:Feil p� smsd' $MAILDRIFT");
		print MAIL "\nsmsd_ok: $dato\t$respons_\n";
		close(MAIL);
	    }

	    $dato = strftime "%d\.%m\.%Y %H:%M:%S", localtime;

	    # Teller antall velykkede sendte meldinger
	    $smsid++;

	    # Setter meldingen lik sendt i databasen
	    $nr1 = $#sendt_id - 1;
	    while (@sendt_id) {
		$id_ = pop @sendt_id;

		$ko2 = "UPDATE smsutko SET sendt=\'Y\',smsid=\'$smsid\',tidsendt=NOW() WHERE id=\'$id_\'";

		&sjekk_conn;
		$ga = &db_execute($conn,$ko2);

		# Skriv til logg
		if ($nr1 == $#sendt_id) {
		    print LOGFIL "Sendt: $dato\t$user\t$hash_ko2_{$id_}\n";
		}
		else {
		    print LOGFIL "  Sendt: $dato\t$user\t$hash_ko2_{$id_}\n";
		}

	    }

	    # Setter meldingen lik ignored i databasen
	    while (@ignored_id) {
		$id_ = pop @ignored_id;

		$ko2 = "UPDATE smsutko SET sendt=\'I\',smsid=\'$smsid\',tidsendt=NOW() WHERE id=\'$id_\'";
		&sjekk_conn;
		$ga = &db_execute($conn,$ko2);

		# Skriv til logg
		print LOGFIL "  Ignored: $dato\t$user\t$hash_ko2_{$id_}\n";
	    }

	}
	else {

	    unless ($smssyk) {

		$smssyk = 1;

		# Skriv logg
		$dato = strftime "%d\.%m\.%Y %H:%M:%S", localtime;
		print LOGFIL "\nError: $dato\t$respons_\n";

		# Send mail
		open(MAIL, "|mail -s 'Feil p� smsd' $MAILDRIFT");
		print MAIL "\nError: $dato\t$respons_\n";
		close(MAIL);

		# Resetter gnokii programmet
		$respons_ = `killall mygnokii`;

	    }		

	    sleep 60;
	}


    }
    
    close(LOGFIL);
    
    # Sjekker om det har kommet noen nye meldinger i mens en har holdt p� � sende.
    &sjekk_ko;
}



sub send_sms {

    my ($tlf, $text) = @_;

	# Fikser spesialtegn som ikke takles av echo og gnokii
	$text =~ s/\(/\\\(/g;
	$text =~ s/\)/\\\)/g;
	$text =~ s/\'/\\\'/g;
	$text =~ s/\"/\\\"/g;
	$text =~ s/\</\\\</g;
	$text =~ s/\>/\\\>/g;

 
	$dato = strftime " %d\/%m %H:%M", localtime; 
	$text = $text.$dato;

    my $res = `echo $text | /usr/local/bin/mygnokii --sendsms TEXT $tlf`;
    
    return ($? >> 8);
    
}

##################################

sub sjekk_conn
{
    my $status = $conn->status;

#    print "Status $status\n";

    unless ($status == 0)
    {
#	print "Resetter $conn\n";

	my $dato_ = strftime " %d\/%m %H:%M", localtime; 
	open(MAIL, "|mail -s 'smsd conn reset' $MAILDRIFT");
	print MAIL "\nStatus: $dato_\t$conn\t $status resatt";
	close(MAIL);

	$conn->reset;
    }
}
##################################

sub justme {
	my $pid;

	if (open PIDFIL, "<$pidfil") {
        $pid = <PIDFIL>;
        kill(0, $pid) and die "\n$0 already running (pid $pid), bailing out\n\n";
        close PIDFIL;
    }
}

##################################

# Finn alle de ekstra gruppene en navngitt bruker er medlem av.
sub usergroups
{
    my $uname = shift;
    my @gids;

    while (my($name, $passwd, $gid, $members) = getgrent()) {
	push(@gids, $gid) if ($members =~ /\b$uname\b/);
    }

    return "@gids";
}

# Dersom vi kj�rer som noen andre enn navcron-brukeren, pr�ver vi �
# tvinge oss selv til � kj�re som denne. Dette vil kun fungere dersom
# root er den som kj�rer scriptet.
sub switchuser
{
    if (getpwnam('navcron')) {
	my ($name,$passwd,$uid,$gid,
	    $quota,$comment,$gcos,$dir,$shell,$expire) = getpwnam('navcron');
	if ($UID != $uid) {
	    my $gids = usergroups('navcron');
	    $GID = "$gid $gids";
	    $UID = $uid;
	    $EGID = "$gid $gids";
	    $EUID = $uid;

	    #print "DEBUG: UID=$UID,GID=$GID,EUID=$EUID,EGID=$EGID\n";

	    $UID == $uid or die "Kan ikke skifte til bruker navcron!";
	}
    } else {
	# Dersom navcron ikke eksisterer p� systemet:
	print STDERR "Advarsel! Kj�rer med root-privilegier!\n";
    }
}

exit(0);
