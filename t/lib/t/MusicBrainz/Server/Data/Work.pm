package t::MusicBrainz::Server::Data::Work;
use Test::Routine;
use Test::Fatal;
use Test::More;
use Test::Deep qw( cmp_deeply methods noclass set );

use MusicBrainz::Server::Data::Work;
use MusicBrainz::Server::Data::WorkType;
use MusicBrainz::Server::Data::Search;

use MusicBrainz::Server::Context;
use MusicBrainz::Server::Test;

with 't::Context';

test 'Test find_by_iswc' => sub {
    my $test = shift;
    MusicBrainz::Server::Test->prepare_test_database($test->c, '+work');

    {
        my @works = $test->c->model('Work')->find_by_iswc('T-000.000.001-0');
        is(@works, 1, 'Found 1 work');
        is($works[0]->id, 1, 'Found work with ID 1');
    }

    {
        my @works = $test->c->model('Work')->find_by_iswc('T-000.000.002-0');
        is(@works, 1, 'Found 1 work');
        is($works[0]->id, 2, 'Found work with ID 1');
    }

    {
        my @works = $test->c->model('Work')->find_by_iswc('T-123.321.002-0');
        is(@works, 0, 'Found 0 works with unknown ISWC');
    }
};

test all => sub {

my $test = shift;
MusicBrainz::Server::Test->prepare_test_database($test->c, '+work');

my $work_data = MusicBrainz::Server::Data::Work->new(c => $test->c);

my $work = $work_data->get_by_id(1);
is ( $work->id, 1 );
is ( $work->gid, "745c079d-374e-4436-9448-da92dedef3ce" );
is ( $work->name, "Dancing Queen" );
is ( $work->type_id, 1 );
is ( $work->edits_pending, 0 );

$work = $work_data->get_by_gid("745c079d-374e-4436-9448-da92dedef3ce");
is ( $work->id, 1 );
is ( $work->gid, "745c079d-374e-4436-9448-da92dedef3ce" );
is ( $work->name, "Dancing Queen" );
is ( $work->type_id, 1 );
is ( $work->edits_pending, 0 );

is ( $work->type, undef );
MusicBrainz::Server::Data::WorkType->new(c => $test->c)->load($work);
is ( $work->type->name, "Aria" );

my $annotation = $work_data->annotation->get_latest(1);
is ( $annotation->text, "Annotation" );


$work = $work_data->get_by_gid('28e73402-5666-4d74-80ab-c3734dc699ea');
is ( $work->id, 1 );

$work = $work_data->get_by_gid('ffffffff-ffff-ffff-ffff-ffffffffffff');
is ( $work, undef );


my $search = MusicBrainz::Server::Data::Search->new(c => $test->c);
my ($results, $hits) = $search->search("work", "queen", 10);
is( $hits, 1 );
is( scalar(@$results), 1 );
is( $results->[0]->position, 1 );
is( $results->[0]->entity->name, "Dancing Queen" );


$test->c->sql->begin;

$work = $work_data->insert({
        name => 'Traits',
        type_id => 1,
        comment => 'Drum & bass track',
    });

ok($work->{id} > 1);

$work = $work_data->get_by_id($work->{id});
is($work->name, 'Traits');
is($work->comment, 'Drum & bass track');
is($work->type_id, 1);
ok(defined $work->gid);

$work_data->update($work->id, {
        name => 'Traits (remix)',
    });

$work = $work_data->get_by_id($work->id);
is($work->name, 'Traits (remix)');

$work_data->delete($work->id);

$work = $work_data->get_by_id($work->id);
ok(!defined $work);

$test->c->sql->commit;

# Both #1 and #2 are in the DB
$work = $work_data->get_by_id(1);
ok(defined $work);
$work = $work_data->get_by_id(2);
ok(defined $work);

# Merge #2 into #1
$test->c->sql->begin;
$work_data->merge(1, 2);
$test->c->sql->commit;

# Only #1 is now in the DB
$work = $work_data->get_by_id(1);
ok(defined $work);
$work = $work_data->get_by_id(2);
ok(!defined $work);

};

test 'Merge with funky relationships' => sub {
    my $test = shift;

    MusicBrainz::Server::Test->prepare_test_database($test->c, <<'EOSQL');
INSERT INTO artist (id, gid, name, sort_name)
    VALUES (1, '5f9913b0-7219-11de-8a39-0800200c9a66', 'Artist', 'Artist');

INSERT INTO work (id, gid, name)
    VALUES (1, '145c079d-374e-4436-9448-da92dedef3cf', 'Target'),
           (2, '245c079d-374e-4436-9448-da92dedef3cf', 'Merge 1'),
           (3, '345c079d-374e-4436-9448-da92dedef3cf', 'Merge 2');

INSERT INTO link (id, link_type, attribute_count) VALUES (1, 167, 0);
INSERT INTO l_artist_work (id, entity0, link, entity1)
    VALUES (1, 1, 1, 2),
           (2, 1, 1, 3);
EOSQL

    $test->c->model('Work')->merge(1, 2, 3);

    my $final_work = $test->c->model('Work')->get_by_id(1);
    $test->c->model('Relationship')->load($final_work);
    is($final_work->all_relationships => 1,
       'Merged work has a single relationship');
    is($final_work->relationships->[0]->link_id => 1,
       'Relationship is of link type 1');
    is($final_work->relationships->[0]->entity0_id => 1,
       'Points to artist 1');
    is($final_work->relationships->[0]->entity1_id => 1,
       'Originates from work 1');
};

test 'Loading work attributes for works with no attributes' => sub {
    my $test = shift;

    MusicBrainz::Server::Test->prepare_test_database($test->c, '+work');

    my $work = $test->c->model('Work')->get_by_id(1);
    is exception { $test->c->model('WorkAttribute')->load_for_works($work) }, undef;

    is($work->all_attributes, 0, 'work has no attributes')
};

test 'Loading work attributes for works with free text attributes' => sub {
    my $test = shift;

    MusicBrainz::Server::Test->prepare_test_database($test->c, '+work');
    $test->c->sql->do(<<EOSQL);
INSERT INTO work_attribute_type (id, name, free_text)
VALUES (1, 'Attribute', true);
EOSQL

    $test->c->model('Work')->set_attributes(
        1,
        {
            attribute_type_id => 1,
            attribute_text => 'Value'
        }
    );

    my $work = $test->c->model('Work')->get_by_id(1);
    is exception { $test->c->model('WorkAttribute')->load_for_works($work) }, undef;

    is($work->all_attributes, 1, 'work has 1 attribute');
    is($work->attributes->[0]->type->name, 'Attribute',
        'has correct attribute name');
    is($work->attributes->[0]->value, 'Value', 'has correct attribute value');
};

test 'Loading work attributes for works with finite values' => sub {
    my $test = shift;

    MusicBrainz::Server::Test->prepare_test_database($test->c, '+work');
    $test->c->sql->do(<<EOSQL);
INSERT INTO work_attribute_type (id, name, free_text)
VALUES (1, 'Attribute', false);
INSERT INTO work_attribute_type_allowed_value (id, work_attribute_type, value)
VALUES (1, 1, 'Value'), (2, 1, 'Value 2');
EOSQL

    $test->c->model('Work')->set_attributes(
        1,
        {
            attribute_type_id => 1,
            attribute_value_id => 1
        }
    );

    my $work = $test->c->model('Work')->get_by_id(1);
    is exception { $test->c->model('WorkAttribute')->load_for_works($work) }, undef;

    is($work->all_attributes, 1, 'work has 1 attribute');
    is($work->attributes->[0]->type->name, 'Attribute',
        'has correct attribute name');
    is($work->attributes->[0]->value, 'Value', 'has correct attribute value');
};

test 'Multiple attributes for a work' => sub {
    my $test = shift;

    MusicBrainz::Server::Test->prepare_test_database($test->c, '+work');
    $test->c->sql->do(<<EOSQL);
INSERT INTO work_attribute_type (id, name, free_text)
VALUES (1, 'Attribute', false), (2, 'Type two', true);
INSERT INTO work_attribute_type_allowed_value (id, work_attribute_type, value)
VALUES (1, 1, 'Value'), (2, 1, 'Value 2');
EOSQL

    $test->c->model('Work')->set_attributes(
        1,
        {
            attribute_type_id => 1,
            attribute_value_id => 2
        },
        {
            attribute_type_id => 2,
            attribute_text => 'Anything you want'
        }
    );

    my $work = $test->c->model('Work')->get_by_id(1);
    is exception { $test->c->model('WorkAttribute')->load_for_works($work) }, undef;

    is($work->all_attributes, 2, 'work has 2 attributes');
};

test 'Determining allowed values for work attributes' => sub {
    my $test = shift;

    $test->c->sql->do(<<EOSQL);
INSERT INTO work_attribute_type (id, name, free_text)
VALUES
  (1, 'Attribute', false),
  (2, 'Free attribute', true),
  (3, 'Attribute 3', false);
INSERT INTO work_attribute_type_allowed_value (id, work_attribute_type, value)
VALUES (1, 1, 'Value'), (2, 1, 'Value 2'), (3, 3, 'Value 3');
EOSQL

    my $types = $test->c->model('WorkAttributeType')->get_by_ids(1..3);
    $test->c->model('WorkAttributeTypeAllowedValue')->load_for_work_attribute_types(values %$types);

    ok($types->{1}->allows_value(1), 'Attribute #1 allows value #1');
    ok($types->{1}->allows_value(2), 'Attribute #1 allows value #2');
    ok(!$types->{1}->allows_value(3), 'Attribute #1 disallows value #3');

    ok($types->{2}->allows_value('Anything you want'),
        'Attribute #2 allows arbitrary text');

    ok($types->{3}->allows_value(3), 'Attribute #3 allows value #3');
};

test 'Merge attributes for works' => sub {
    my $test = shift;

    my $work_data = $test->c->model('Work');

    $test->c->sql->do(<<EOSQL);
INSERT INTO work_attribute_type (id, name, free_text)
VALUES
  (1, 'Attribute', false),
  (2, 'Free attribute', true),
  (3, 'Attribute 3', false);
INSERT INTO work_attribute_type_allowed_value (id, work_attribute_type, value)
VALUES (1, 1, 'Value'), (2, 1, 'Value 2'), (3, 3, 'Value 3');
EOSQL

    my $a = $work_data->insert({ name => 'Traits' });
    my $b = $work_data->insert({ name => 'Tru Beat' });

    $work_data->set_attributes(
        $a->{id},
        { attribute_type_id => 1, attribute_value_id => 1 },
        { attribute_type_id => 2, attribute_text => 'Free Text' }
    );

    $work_data->set_attributes(
        $b->{id},
        { attribute_type_id => 1, attribute_value_id => 1 },
        { attribute_type_id => 1, attribute_value_id => 2 },
        { attribute_type_id => 3, attribute_value_id => 3 },
        { attribute_type_id => 2, attribute_text => 'Free Text' }
    );

    $work_data->merge($a->{id}, $b->{id});

    my $final_work = $work_data->get_by_gid($a->{gid});
    $test->c->model('WorkAttribute')->load_for_works($final_work);

    cmp_deeply(
        $final_work->attributes,
        set(
            methods(
                type => methods(id => 1),
                value_id => 1
            ),
            methods(
                type => methods(id => 1),
                value_id => 2
            ),
            methods(
                type => methods(id => 2),
                value => "Free Text"
            ),
            methods(
                type => methods(id => 3),
                value_id => 3
            )
        )
    )
};

test 'Deleting a work with work attributes' => sub {
    my $test = shift;

    my $work_data = $test->c->model('Work');

    $test->c->sql->do(<<EOSQL);
INSERT INTO work_attribute_type (id, name, free_text) VALUES (1, 'Attribute', false);
INSERT INTO work_attribute_type_allowed_value (id, work_attribute_type, value) VALUES (1, 1, 'Value');
EOSQL

    my $a = $work_data->insert({ name => 'Foo' });

    $work_data->set_attributes(
        $a->{id},
        { attribute_type_id => 1, attribute_value_id => 1 },
    );

    ok !exception { $work_data->delete($a->{id}); }
};

test 'Deleting a work that\'s in a collection' => sub {
    my $test = shift;
    my $c = $test->c;

    MusicBrainz::Server::Test->prepare_test_database($c, '+work');

    $c->sql->do(<<'EOSQL');
INSERT INTO editor (id, name, password, ha1) VALUES (5, 'me', '{CLEARTEXT}mb', 'a152e69b4cf029912ac2dd9742d8a9fc');
EOSQL

    my $work = $c->model('Work')->insert({ name => 'Test123' });

    my $collection = $c->model('Collection')->insert(5, {
        description => '',
        editor_id => 5,
        name => 'Collection123',
        public => 0,
        type_id => 15,
    });

    $c->model('Collection')->add_entities_to_collection('work', $collection->{id}, $work->{id});
    $c->model('Work')->delete($work->{id});

    ok(!$c->model('Work')->get_by_id($work->{id}));
};

test 'Merging a work that\'s in a collection' => sub {
    my $test = shift;
    my $c = $test->c;

    MusicBrainz::Server::Test->prepare_test_database($c, '+work');

    $c->sql->do(<<'EOSQL');
INSERT INTO editor (id, name, password, ha1) VALUES (5, 'me', '{CLEARTEXT}mb', 'a152e69b4cf029912ac2dd9742d8a9fc');
EOSQL

    my $work1 = $c->model('Work')->insert({ name => 'Test123' });
    my $work2 = $c->model('Work')->insert({ name => 'Test456' });

    my $collection = $c->model('Collection')->insert(5, {
        description => '',
        editor_id => 5,
        name => 'Collection123',
        public => 0,
        type_id => 15,
    });

    $c->model('Collection')->add_entities_to_collection('work', $collection->{id}, $work1->{id});
    $c->model('Work')->merge($work2->{id}, $work1->{id});

    ok($c->sql->select_single_value('SELECT 1 FROM editor_collection_work WHERE work = ?', $work2->{id}))
};

1;
