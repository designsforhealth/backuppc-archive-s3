#!/usr/bin/perl
#============================================================= -*-perl-*-
#
# BackupPC_archivePipeApi.pl: get backup and archive info from BackupPC
#
# DESCRIPTION
#  
#   Usage: BackupPC_archivePipeApi.pl -a <archiveHost> [-h <host> -g]|[-G]
#
#   Provides various functions for external integration with BackupPC
#
# AUTHOR
#   Johnny Walker <jwalker@ashley-martin.com>
#
# COPYRIGHT
#   Copyright (C) 2014 Johnny Walker
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#========================================================================
#
# Version 1.0.0, released 11 Jun 2014.
#
# See http://backuppc.sourceforge.net.
#
#========================================================================

use strict;
no  utf8;
use lib qw(/usr/share/backuppc/lib /usr/share/BackupPC/lib);
use Getopt::Std;
use List::Util qw(first);
use JSON::PP;
use BackupPC::Lib;

our %ArchiveReq;

die("BackupPC::Lib->new failed\n") if ( !(my $bpc = BackupPC::Lib->new) );

my %opts;
my $json = JSON::PP->new->utf8->pretty->allow_nonref;

if (!getopts("a:h:gG", \%opts)) {
    print STDERR <<EOF;
usage: $0 -a <archiveHost> [-h <host> -g]|[-G]
EOF
    exit(1);
}

if ($opts{a} ne "" && $opts{h} ne "" && $opts{g}) {
	my ($host, $hostLastBackup, $lastHostArchive) = &get_backup_info_for_host($opts{h}, $opts{a});
	
	my $output = $json->encode({ 
		'GetLastBackupAndArchiveForHost' => {
			'HostInfo' => $host,
			'LastBackup' => $hostLastBackup,
			'LastArchive' => $lastHostArchive
		} 
	});
	
	print "$output\n";
}
elsif ($opts{a} ne "" && $opts{G}) {
	my @hosts = &get_hosts($opts{a});
	
	my %outputHash = ();
	foreach my $hostName (@hosts) {
		my ($host, $hostLastBackup, $lastHostArchive) = &get_backup_info_for_host($hostName, $opts{a});
		
		$outputHash{$hostName} = {
			'HostInfo' => $host,
			'LastBackup' => $hostLastBackup,
			'LastArchive' => $lastHostArchive
		};
	}
	
	my $output = $json->encode({
		'GetLastBackupAndArchiveForAllHosts' => \%outputHash
	});
	
	print "$output\n";
}
else {
    print STDERR <<EOF;
usage: $0 -a <archiveHost> [-h <host> -g]|[-G]
EOF
    exit(1);
}

sub get_hosts {
	my $archiveHost = lc(shift);
	my $hosts = $bpc->HostInfoRead();
	return grep { lc($_) ne $archiveHost } keys %$hosts;
}

sub get_backup_info_for_host {
	my ($argHost, $argArchiveHost) = @_;

	my $host = $bpc->HostInfoRead($argHost);
	if (!%$host) {
		print(STDERR "$0: host \"$argHost\" doesn't exist... quitting\n");
		exit(1);
	}
	my $archiveHost = $bpc->HostInfoRead($argArchiveHost);
	if (!%$archiveHost) {
		print(STDERR "$0: archive host \"$argArchiveHost\" doesn't exist... quitting\n");
		exit(1);
	}
	
	# my $hostName = (keys %$host)[0];
	# my $archiveHostName = (keys %$archiveHost)[0];
	$host = $host->{(keys %$host)[0]};
	my $hostName = lc($host->{host});
	$archiveHost = $archiveHost->{(keys %$archiveHost)[0]};
	my $archiveHostName = lc($archiveHost->{host});
	# print Data::Dumper->Dump([$host, $host->{host}]);
	# print Data::Dumper->Dump([$archiveHost, $archiveHost->{host}]);
	
    my @hostBackups = $bpc->BackupInfoRead($hostName);
    my @archiveHostBackups = $bpc->ArchiveInfoRead($archiveHostName);

	my $hostLastBackup = {};
	if (@hostBackups) {
		# make sort the backups to ensure we've got the last one
		my @sorted = sort { $a->{num} <=> $b->{num} } @hostBackups;
		$hostLastBackup = pop @sorted;
	}
	
	# print Data::Dumper->Dump([{ $host->{host} => \@hostBackups }]);
	# print Data::Dumper->Dump([{ $host->{host} => $hostLastBackup }]);
	# print Data::Dumper->Dump([{ $archiveHost->{host} => \@archiveHostBackups}]);
	
	my $TopDir = $bpc->TopDir();
	
	# if the host has a backup, let's try and find a matching archive
	my %lastHostArchive = ();
	if (keys %$hostLastBackup) {
		# start by finding all the archives that finished successfully
		my @filteredArchives = reverse
							   sort { $a->{num} <=> $b->{num} }
							   grep { $_->{result} eq 'ok' } @archiveHostBackups;
		
		foreach my $archive (@filteredArchives) {
		    %ArchiveReq = ();
		    do "$TopDir/pc/$archiveHostName/ArchiveInfo.$archive->{num}"
			    if ( -f "$TopDir/pc/$archiveHostName/ArchiveInfo.$archive->{num}" );
			my $index = first { lc($_) eq $hostName } @{$ArchiveReq{HostList}};		
			if ($index) {
				my $backupNum = $ArchiveReq{BackupList}[$index];
				
				$lastHostArchive{ArchiveInfo} = $archive;
				$lastHostArchive{ArchiveReq} = \%ArchiveReq;
				$lastHostArchive{Summary} = { 
					'host' => $hostName, 'hostBackupNum' => $backupNum, 'archiveNum' => $archive->{num}
				};
				last;
			}
		}
	}
	
	return ($host, $hostLastBackup, \%lastHostArchive);
}
exit(0);
