#!/usr/bin/perl
# Every pay phone the server's maps put down, read out of the lotpacks.
#
#   perl scripts/phones.pl                  # CSV of every phone to stdout
#   perl scripts/phones.pl --summary        # counts by map, to stderr as well
#   perl scripts/phones.pl --every          # every map's phones, no precedence
#   perl scripts/phones.pl --lua > FILE     # shared/PhunTaxi/map_phones.lua
#
# Where things are, overridable from the environment:
#
#   PZ_SERVER_INI  C:/Users/samue/Zomboid/Server/servertest.ini
#   PZ_MAP_ROOTS   ;-separated folders holding mod folders, searched in order
#   PZ_VANILLA     the game's media/maps folder
#
# The map set and its order are the ini's Map= line. The first map in that
# list to carry a cell owns it, as the game does, so a custom map that
# rebuilds a vanilla cell hides the vanilla phones there. A map name found in
# more than one mod folder is settled by which mod id is in Mods=.
#
# --every and --lua drop the precedence: each map gives all of its phones,
# since another server may run it without the map that hides some here. The
# mod still keeps a phone the game does not load from being put up: a map
# phone goes up only over the vanilla phone it names, so one that is not
# there is dropped when its square loads. --lua writes each map's phones under
# its mod id, so none is offered on a server without that mod, and a square
# two maps share once, with both ids. Our own sprites are left out: one of
# ours standing on a map is recorded when its square loads or it is used.
#
# Checked in game (Raven Creek B42, 2026-09-30): three phones in a line, each
# facing the next (4286..4288,15491 E), are a row of booths, and two phones
# at the same x,y on floors 1 to 4 (5094,15546) are banks at the top of a
# stairwell. Both swap and stand fine, so neither is filtered out.
#
# Each phone also gets the room that names it (the CSV's last column, the
# fifth field in --lua): the phone's own room when it says something, or
# else the biggest telling room of its building, with the square in front
# and the one behind tried when the phone's own square is in no room. A
# booth, a building of generic rooms (%generic) or a mall of many shops gets
# none. Core.phones.roomWords turns it into the label.
#
# A cell whose lotheader does not name a phone sprite is never decoded, so a
# full run touches a few hundred lotpacks out of four thousand.
#
# FORMAT: PhunInteriors' scripts/tiles.pl has the lotpack layout. One thing
# it leaves out: after the tile names the lotheader carries width, height,
# minLevel, maxLevel, and the lotpack's 64 entry levels start at minLevel,
# not at 0. Cell 10_56 (minLevel -1) shows it: stream level 0 is 781 squares
# of basement and stream level 1 is 65536 squares of ground.

use strict;
use warnings;

my $summary = grep { $_ eq '--summary' } @ARGV;
my $lua = grep { $_ eq '--lua' } @ARGV;
my $every = $lua || grep { $_ eq '--every' } @ARGV;

my $ini = $ENV{PZ_SERVER_INI} // 'C:/Users/samue/Zomboid/Server/servertest.ini';
my @roots = split /;/, ($ENV{PZ_MAP_ROOTS} //
    'C:/Users/samue/Zomboid/mods;C:/Users/samue/Zomboid/123mods;D:/Steam/steamapps/workshop/content/108600');
my $vanilla = $ENV{PZ_VANILLA} // 'D:/Steam/steamapps/common/ProjectZomboid/media/maps';

# The sprite -> facing table in shared/PhunTaxi/phones.lua, vanilla targets
# and our own, so a map that already places one of ours is reported too.
my %facing = (
    street_decoration_01_38 => 'E', street_decoration_01_39 => 'S',
    street_decoration_01_46 => 'W', street_decoration_01_47 => 'N',
    phuninteriors_01_16 => 'E', phuninteriors_01_17 => 'S',
    phuninteriors_01_18 => 'W', phuninteriors_01_19 => 'N',
);

# Git Bash's perl wants /c/..., a Windows perl wants C:/...; take either.
sub native {
    my ($p) = @_;
    return $p if -e $p;
    (my $m = $p) =~ s{^([A-Za-z]):[\/\\]}{"/" . lc($1) . "/"}e;
    return -e $m ? $m : $p;
}
$ini = native($ini);
$vanilla = native($vanilla);
@roots = map { native($_) } @roots;

local $/;

open(my $fi, '<', $ini) or die "$ini: $!\n";
my $cfg = <$fi>;
my ($mapLine) = $cfg =~ /^Map=(.*?)\r?$/m or die "no Map= in $ini\n";
my ($modLine) = $cfg =~ /^Mods=(.*?)\r?$/m;
my %active = map { s/^\\//r => 1 } split /;/, ($modLine // '');
my @maps = grep { length } split /;/, $mapLine;

sub slurp {
    my ($p) = @_;
    open(my $f, '<:raw', $p) or return undef;
    return <$f>;
}

# The mod id owning a map folder: the nearest mod.info going up.
sub modId {
    my ($dir) = @_;
    for (1 .. 4) {
        $dir =~ s{/[^/]+$}{} or last;
        for my $info ("$dir/mod.info", "$dir/42/mod.info", "$dir/common/mod.info") {
            my $t = slurp($info) // next;
            return $1 if $t =~ /^id=\s*(.*?)\s*\r?$/m;
        }
    }
    return '';
}

sub subdirs {
    my ($dir) = @_;
    opendir(my $dh, $dir) or return ();
    return map { "$dir/$_" } grep { !/^\./ and -d "$dir/$_" } readdir $dh;
}

sub lotheaders {
    my ($dir) = @_;
    opendir(my $dh, $dir) or return ();
    return map { /^(\d+)_(\d+)\.lotheader$/ ? "$1_$2" : () } readdir $dh;
}

sub folderFor {
    my ($name) = @_;
    return ("$vanilla/$name", "vanilla") if lotheaders("$vanilla/$name");
    my @found;
    for my $root (@roots) {
        # A mod folder directly (mods/), or a Workshop item holding mods/.
        my @mods = map { ($_, subdirs("$_/mods")) } subdirs($root);
        for my $m (@mods) {
            push @found, grep { -d } map { "$m/$_/media/maps/$name" } qw(42 common);
        }
    }
    return () unless @found;
    my @live = grep { $active{modId($_)} } @found;
    my $pick = (@live ? $live[0] : $found[0]);
    return ($pick, modId($pick));
}

# Parse a lotheader: tile names, then width, height, minLevel, maxLevel.
sub header {
    my ($d) = @_;
    return undef unless defined $d and substr($d, 0, 4) eq 'LOTH';
    my $n = unpack('V', substr($d, 8, 4));
    my ($p, @names) = (12);
    for (1 .. $n) {
        my $e = index($d, "\n", $p);
        return undef if $e < 0;
        push @names, substr($d, $p, $e - $p);
        $p = $e + 1;
    }
    my (undef, undef, $lo, $hi) = unpack('l<4', substr($d, $p, 16));
    return { names => \@names, lo => $lo, hi => $hi, data => $d, rooms => $p + 16 };
}

# The room defs that follow, and the buildings made of them, read only for a
# cell with a phone in it. A room is a name, a level, its rects in cell
# coordinates and objects we skip (PhunInteriors' scripts/rooms.pl); then a
# count of buildings, each a count of room indexes and the indexes; then the
# 1024 byte zombie tail. Checked on all 4065 vanilla cells: every index is a
# room and the buildings end exactly 1024 bytes from the end.
sub rooms {
    my ($h) = @_;
    my ($d, $p) = ($h->{data}, $h->{rooms});
    my $n = unpack('V', substr($d, $p, 4));
    $p += 4;
    my @rooms;
    for (1 .. $n) {
        my $e = index($d, "\n", $p);
        return [] if $e < 0;
        my $name = substr($d, $p, $e - $p);
        $p = $e + 1;
        my ($level, $count) = unpack('l<V', substr($d, $p, 8));
        $p += 8;
        my @rects = map { [unpack('V4', substr($d, $p + $_ * 16, 16))] } 0 .. $count - 1;
        $p += $count * 16;
        $p += 4 + unpack('V', substr($d, $p, 4)) * 12;
        my $area = 0;
        $area += $_->[2] * $_->[3] for @rects;
        push @rooms, { name => $name, level => $level, rects => \@rects, area => $area };
    }
    my $b = unpack('V', substr($d, $p, 4));
    $p += 4;
    for my $i (0 .. $b - 1) {
        my $count = unpack('V', substr($d, $p, 4));
        my @ids = unpack("V$count", substr($d, $p + 4, $count * 4));
        $p += 4 + $count * 4;
        my $building = [grep { defined } map { $rooms[$_] } @ids];
        $_->{building} = $building for @$building;
    }
    return \@rooms;
}

# The room a square in the cell is in, or undef.
sub roomAt {
    my ($rooms, $x, $y, $z) = @_;
    for my $r (@$rooms) {
        next unless $r->{level} == $z;
        for my $q (@{ $r->{rects} }) {
            return $r if $x >= $q->[0] and $x < $q->[0] + $q->[2] and $y >= $q->[1] and $y < $q->[1] + $q->[3];
        }
    }
    return undef;
}

# Where the character stands, as Core.phones.front has it.
my %front = (E => [1, 0], S => [0, 1], W => [-1, 0], N => [0, -1]);

# Room names that say what a room is and not what the building is: a hospital
# has a hall, and so does a house. A building is named after its biggest room
# that is not one of these, and one with nothing else is not named.
my %generic = map { $_ => 1 } qw(
    hall hallway secondaryhall corridor foyer lobby entry stairs
    livingroom bedroom bathroom kitchen diningroom closet laundry
    storage storageunit empty emptyoutside emptycommercial vacated
    breakroom janitor office officestorage garagestorage garage shed
    post aesthetic basement stairwell roofstairs locker all
);
sub generic {
    my ($name) = @_;
    $name = lc $name;
    return $generic{$name} || $name =~ /^room\d*$/;
}

# More different telling rooms than this and the building is a mall or a
# block of shops, and naming it after its biggest one would be a guess.
my $MALL = 4;

# Smaller than this, in squares, a building is a booth or a kiosk a mapper
# boxed in: Raven Creek puts each street phone in a one square building of
# "post" and "livingroom".
my $BOOTH = 9;

# What a phone is in, as a room name: the building its own square, the one in
# front or the one behind (for a phone on an outside wall) is part of. Squares
# off the cell's edge are not looked at: the neighbour's rooms are not in this
# header. Empty for a phone in the street or in a building with no telling
# room, which Lua labels by its zone alone.
sub phoneRoom {
    my ($rooms, $x, $y, $z, $facing) = @_;
    my ($dx, $dy) = @{ $front{$facing} };
    for my $s ([$x, $y], [$x + $dx, $y + $dy], [$x - $dx, $y - $dy]) {
        next if $s->[0] < 0 or $s->[1] < 0 or $s->[0] > 255 or $s->[1] > 255;
        my $room = roomAt($rooms, $s->[0], $s->[1], $z) // next;
        my @in = @{ $room->{building} // [$room] };
        my $area = 0;
        $area += $_->{area} for @in;
        return '' if $area < $BOOTH;
        return lc $room->{name} unless generic($room->{name});
        my @telling = sort { $b->{area} <=> $a->{area} || $a->{name} cmp $b->{name} }
            grep { !generic($_->{name}) } @in;
        my %kinds = map { lc $_->{name} => 1 } @telling;
        return '' if !@telling or keys %kinds > $MALL;
        return lc $telling[0]{name};
    }
    return '';
}

my (%owner, @phones, %stats, @missing);

for my $i (0 .. $#maps) {
    my $name = $maps[$i];
    my ($dir, $mod) = folderFor($name);
    unless ($dir) {
        push @missing, $name;
        next;
    }
    my @cells = sort(lotheaders($dir));
    my $st = $stats{$name} = { order => $i, dir => $dir, mod => $mod, cells => 0, won => 0, phoneCells => 0, phones => 0 };
    for my $cell (@cells) {
        $st->{cells}++;
        next if exists $owner{$cell} and not $every;
        $st->{won}++ unless exists $owner{$cell};
        $owner{$cell} //= $name;

        my $h = header(slurp("$dir/$cell.lotheader"));
        unless ($h) {
            warn "$name $cell: lotheader did not parse\n";
            next;
        }
        my %want;
        for my $k (0 .. $#{ $h->{names} }) {
            $want{$k} = $h->{names}[$k] if $facing{ $h->{names}[$k] };
        }
        next unless %want;
        $st->{phoneCells}++;

        my $d = slurp("$dir/world_$cell.lotpack");
        unless (defined $d and substr($d, 0, 4) eq 'LOTP') {
            warn "$name $cell: no lotpack\n";
            next;
        }
        my ($cx, $cy) = split /_/, $cell;
        my $rooms = rooms($h);
        # Not the int at 8, which tiles.pl reads as the chunk count: it is
        # 1024 in vanilla and 8 in Raven Creek B42, whose table still holds
        # 1024 offsets. The table ends where the first chunk begins.
        my $chunks = (unpack('V', substr($d, 12, 4)) - 12) / 8;
        my @off = map { unpack('V', substr($d, 12 + $_ * 8, 4)) } 0 .. $chunks - 1;
        my $found = 0;
        for my $c (0 .. $chunks - 1) {
            my ($p, $end) = ($off[$c], $c < $chunks - 1 ? $off[$c + 1] : length $d);
            my ($chx, $chy, $e) = (int($c / 32), $c % 32, 0);
            while ($p + 4 <= $end) {
                my $cnt = unpack('l<', substr($d, $p, 4));
                $p += 4;
                if ($cnt == -1) {
                    $e += unpack('l<', substr($d, $p, 4));
                    $p += 4;
                    next;
                }
                last if $cnt <= 0 or $p + $cnt * 4 > $end;
                my @v = unpack("l<$cnt", substr($d, $p, $cnt * 4));
                $p += $cnt * 4;
                for my $t (@v[1 .. $#v]) {
                    my $sprite = $want{$t} // next;
                    my $s = $e % 64;
                    my ($lx, $ly, $z) = ($chx * 8 + int($s / 8), $chy * 8 + $s % 8, $h->{lo} + int($e / 64));
                    push @phones, [
                        $cx * 256 + $lx, $cy * 256 + $ly, $z,
                        $sprite, $facing{$sprite}, $name, $cx, $cy, $mod,
                        phoneRoom($rooms, $lx, $ly, $z, $facing{$sprite}),
                    ];
                    $found++;
                }
                $e++;
            }
        }
        # A header names a sprite for the whole cell palette; one that
        # decodes to nothing means the decode or the palette is off.
        warn "$name $cell: header names a phone, lotpack has none\n" unless $found;
        $st->{phones} += $found;
    }
}

my @sorted = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] } @phones;

if ($lua) {
    # One entry per square. Vanilla on it means every server has it, so it
    # carries no mods; otherwise every map mod that places it.
    my (%at, @keys);
    for my $p (grep { $_->[3] !~ /^phuninteriors/ } @sorted) {
        my $key = "$p->[0]_$p->[1]_$p->[2]";
        push @keys, $key unless $at{$key};
        my $e = $at{$key} //= { p => $p, mods => {}, maps => {} };
        $e->{mods}{ $p->[8] eq 'vanilla' ? '' : $p->[8] } = 1;
        $e->{maps}{ $p->[5] } = 1;
    }
    my (%groups, %groupMaps, @order);
    for my $key (@keys) {
        my $e = $at{$key};
        my $set = exists $e->{mods}{''} ? '' : join(';', sort keys %{ $e->{mods} });
        push @order, $set unless $groups{$set};
        push @{ $groups{$set} }, $e->{p};
        $groupMaps{$set}{$_} = 1 for keys %{ $e->{maps} };
    }
    my $n = scalar @keys;
    print <<"EOF";
require "PhunTaxi/phones"
local Core = PhunTaxi

-- ---------------------------------------------------------------------------
-- The pay phones the maps put down, $n of them. GENERATED by
-- scripts/phones.pl --lua from the lotpacks of every map in the server's
-- Map= list: run it again when that list changes, and do not edit by hand.
--
-- Each is offered with Core.addMapPhone, so it goes up only over the vanilla
-- phone it names, at PhoneChance, spaced by PhoneDistance like every other
-- candidate. A phone a map update moved is dropped when its square loads
-- without one; an admin can keep the real one from the setup menu.
--
-- Grouped by the mods whose maps place it: no mods is vanilla.
-- {x, y, z, facing, room}, the PHONE's square. The room, when there is one,
-- is the building it is in or on, which names it (Core.phones.roomWords).
-- ---------------------------------------------------------------------------

local groups = {
EOF
    for my $set (sort { ($a ne '') <=> ($b ne '') || $a cmp $b } @order) {
        my @mods = $set eq '' ? () : split /;/, $set;
        printf "    {\n        -- %s\n", join(', ', sort keys %{ $groupMaps{$set} });
        printf "        mods = {%s},\n", join(', ', map { "\"$_\"" } @mods) if @mods;
        print "        phones = {\n";
        print join(",\n", map {
            sprintf('            {%d, %d, %d, "%s"%s}', @$_[0 .. 2], $_->[4], $_->[9] ne '' ? qq(, "$_->[9]") : '')
        } @{ $groups{$set} }), "\n";
        print "        }\n    },\n";
    }
    print <<'EOF';
}

for _, group in ipairs(groups) do
    for _, p in ipairs(group.phones) do
        Core.addMapPhone(p[1], p[2], p[3], p[4], group.mods, p[5])
    end
end

return Core
EOF
    exit;
}

print "x,y,z,sprite,facing,map,cx,cy,mod,room\n";
print join(',', map { /[,"]/ ? "\"$_\"" : $_ } @$_), "\n" for @sorted;

if ($summary) {
    my $total = 0;
    printf STDERR "%-36s %6s %6s %6s %6s  %s\n", 'map', 'cells', 'won', 'pcells', 'phones', 'mod';
    for my $n (sort { $stats{$a}{order} <=> $stats{$b}{order} } keys %stats) {
        my $s = $stats{$n};
        $total += $s->{phones};
        printf STDERR "%-36s %6d %6d %6d %6d  %s\n", $n, @$s{qw(cells won phoneCells phones mod)};
    }
    my %byFacing;
    $byFacing{ $_->[4] }++ for @phones;
    printf STDERR "\n%d phones, %s\n", $total, join(' ', map { "$_=$byFacing{$_}" } sort keys %byFacing);
    printf STDERR "not found: %s\n", join('; ', @missing) if @missing;
}
