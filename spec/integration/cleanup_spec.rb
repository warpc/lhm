# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require File.expand_path(File.dirname(__FILE__)) + '/integration_helper'

describe Lhm, 'cleanup' do
  include IntegrationHelper
  before(:each) { connect_master! }

  describe 'changes' do
    before(:each) do
      table_create(:users)
      table_create(:permissions)
      simulate_failed_migration do
        Lhm.change_table(:users, :atomic_switch => false) do |t|
          t.add_column(:logins, "INT(12) DEFAULT '0'")
          t.add_index(:logins)
        end
      end
      simulate_failed_migration do
        Lhm.change_table(:permissions, :atomic_switch => false) do |t|
          t.add_column(:user_id, "INT(12) DEFAULT '0'")
          t.add_index(:user_id)
        end
      end
    end

    after(:each) do
      Lhm.cleanup(true)
    end

    describe 'cleanup' do
      it 'should show temporary tables' do
        output = capture_stdout do
          Lhm.cleanup
        end
        output.must_include('Would drop LHM backup tables')
        output.must_match(/lhma_[0-9_]*_users/)
        output.must_match(/lhma_[0-9_]*_permissions/)
      end

      it 'should show temporary tables within range' do
        table = OpenStruct.new(:name => 'users')
        table_name = Lhm::Migration.new(table, nil, nil, {}, Time.now - 172800).archive_name
        table_rename(:users, table_name)

        table2 = OpenStruct.new(:name => 'permissions')
        table_name2 = Lhm::Migration.new(table2, nil, nil, {}, Time.now - 172800).archive_name
        table_rename(:permissions, table_name2)

        output = capture_stdout do
          Lhm.cleanup false, { :until => Time.now - 86400 }
        end
        output.must_include('Would drop LHM backup tables')
        output.must_match(/lhma_[0-9_]*_users/)
        output.must_match(/lhma_[0-9_]*_permissions/)
      end

      it 'should exclude temporary tables outside range' do
        table = OpenStruct.new(:name => 'users')
        table_name = Lhm::Migration.new(table, nil, nil, {}, Time.now).archive_name
        table_rename(:users, table_name)

        table2 = OpenStruct.new(:name => 'permissions')
        table_name2 = Lhm::Migration.new(table2, nil, nil, {}, Time.now).archive_name
        table_rename(:permissions, table_name2)

        output = capture_stdout do
          Lhm.cleanup false, { :until => Time.now - 172800 }
        end
        output.must_include('Would drop LHM backup tables')
        output.wont_match(/lhma_[0-9_]*_users/)
        output.wont_match(/lhma_[0-9_]*_permissions/)
      end

      it 'should show temporary triggers' do
        output = capture_stdout do
          Lhm.cleanup
        end
        output.must_include('Would drop LHM triggers')
        output.must_include('lhmt_ins_users')
        output.must_include('lhmt_del_users')
        output.must_include('lhmt_upd_users')
        output.must_include('lhmt_ins_permissions')
        output.must_include('lhmt_del_permissions')
        output.must_include('lhmt_upd_permissions')
      end

      it 'should delete temporary tables' do
        Lhm.cleanup(true).must_equal(true)
        Lhm.cleanup.must_equal(true)
      end
    end

    describe 'cleanup_current_run' do
      it 'should show lhmn table for the specified table only' do
        table_create(:permissions)
        table_rename(:permissions, 'lhmn_permissions')
        output = capture_stdout do
          Lhm.cleanup_current_run(false, 'permissions')
        end
        output.must_include('Would drop LHM backup tables')
        output.must_match(/lhmn_permissions/)
        output.wont_match(/lhma_[0-9_]*_permissions/)
        output.wont_match(/lhma_[0-9_]*_users/)
      end

      it 'should show temporary triggers for the specified table only' do
        output = capture_stdout do
          Lhm.cleanup_current_run(false, 'permissions')
        end
        output.must_include('Would drop LHM triggers')
        output.wont_include('lhmt_ins_users')
        output.wont_include('lhmt_del_users')
        output.wont_include('lhmt_upd_users')
        output.must_include('lhmt_ins_permissions')
        output.must_include('lhmt_del_permissions')
        output.must_include('lhmt_upd_permissions')
      end

      it 'should delete temporary tables and triggers for the specified table only' do
        assert Lhm.cleanup_current_run(true, 'permissions')

        all_tables = Lhm.connection.select_values('show tables')
        all_triggers = Lhm.connection.select_values('show triggers')

        refute all_tables.include?('lhmn_permissions')
        assert all_tables.find { |t| t =~ /lhma_(.*)_users/}

        refute all_triggers.find { |t| t =~ /lhmt_(.*)_permissions/}
        assert all_triggers.find { |t| t =~ /lhmt_(.*)_users/}
      end
    end
  end
end
