require 'test_helper'

# Stress coverage for the "emptylist bandaid" refcount investigation
# (see the "Emptylist bandaid refcounting bug" tracking card). These tests
# target update_waif_propdefs() (src/waif.cc), which transfers Vars
# (including {}-valued waif properties) through a function-static scratch
# buffer via raw struct assignment, not var_ref(). That's only safe if the
# function is never reentered while a fill/copy-back cycle is in flight.
# Static analysis of the current call graph found no synchronous C-call-stack
# path back into the function from within itself, so this is an empirical
# stress pass rather than a targeted reproduction of a known trigger.
#
# Independent of whether this ever turns up the historical bug, these tests
# are new coverage of previously-untested territory: heavy waif propdef
# churn (chparent/add_property/delete_property) interleaved with many
# forked tasks concurrently reading/writing {}-valued waif properties.
class TestWaifStress < Test::Unit::TestCase

  def setup
    run_test_as('wizard') do
      command(%Q|; for t in (queued_tasks()); kill_task(t[1]); endfor;|)
    end
  end

  def test_that_concurrent_waif_propdef_churn_does_not_corrupt_emptylist
    run_test_as('wizard') do
      base = create(:waif)
      add_property(base, ':a', {}, [player, ''])
      add_property(base, ':b', {}, [player, ''])

      class_a = create(base)
      add_property(class_a, ':c', {}, [player, ''])

      class_b = create(base)
      add_property(class_b, ':d', {}, [player, ''])

      worker = create(class_a)

      add_verb(worker, ['player', 'xd', 'hammer'], ['this', 'none', 'this'])
      set_verb_code(worker, 'hammer') do |vc|
        lines = <<-EOF
          stash = {};
          for i in [1..20]
            w = #{worker}:new();
            try
              x = w.a;
            except e (ANY)
            endtry
            try
              x = w.b;
            except e (ANY)
            endtry
            try
              x = w.c;
            except e (ANY)
            endtry
            try
              x = w.d;
            except e (ANY)
            endtry
            stash = listappend(stash, w);
            suspend(0);
          endfor
          return length(stash);
        EOF
        lines.split("\n").each { |line| vc << line }
      end

      simplify(command(%Q|; for i in [1..15] fork (0) #{worker}:hammer(); endfork endfor return 1;|))

      15.times do |round|
        prop = "z#{round}"
        add_property(class_a, prop, {}, [player, ''])
        simplify(command('; suspend(0); return 1;'))
        delete_property(class_a, prop)
        simplify(command('; suspend(0); return 1;'))
        # Alternate the worker's own parent between two sibling classes with
        # different {}-valued properties, forcing waif->propdefs to go out
        # of sync with classp->waif_propdefs and reconcile on next access.
        chparent(worker, round.even? ? class_b : class_a)
        simplify(command('; suspend(0); return 1;'))
      end

      # Drain remaining forked tasks.
      60.times { simplify(command('; suspend(0); return 1;')) }

      if has_function?('debug_emptylist_refcount')
        rc = simplify(command('; return debug_emptylist_refcount();'))
        assert rc.is_a?(Integer) && rc > 0, "emptylist refcount corrupted or wrapped: #{rc.inspect}"
      end
    end
  end

end
