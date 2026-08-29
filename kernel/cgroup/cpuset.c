/*
 * DroidSpaces cgroup v2 compatibility wrapper for the Android 4.19 cpuset.
 *
 * The vendor 4.19 scheduler is not safe to drive through the legacy cpuset
 * scheduler-domain rebuild path when cpuset is used on the cgroup v2
 * hierarchy. Keep the upstream/backported cpuset implementation intact,
 * but make the two scheduler-facing operations safe for v2:
 *
 *  - task affinity is always forced through effective_cpus;
 *  - scheduler-domain rebuild requests are discarded in v2.
 *
 * The original implementation lives in cpuset_v2_legacy.c so that this
 * compatibility layer can be kept small and auditable.
 */

/* Keep the real scheduler API declarations visible before macro redirection. */
#include <linux/sched.h>

static int droidspaces_set_cpus_allowed_ptr(struct task_struct *p,
						const struct cpumask *new_mask);
#ifdef CONFIG_SMP
static void droidspaces_partition_sched_domains(int ndoms_new,
						 cpumask_var_t doms_new[],
						 struct sched_domain_attr *dattr_new);
#endif

#define set_cpus_allowed_ptr droidspaces_set_cpus_allowed_ptr
#define partition_sched_domains droidspaces_partition_sched_domains
#include "cpuset_v2_legacy.c"
#undef set_cpus_allowed_ptr
#undef partition_sched_domains

static int droidspaces_set_cpus_allowed_ptr(struct task_struct *p,
						const struct cpumask *new_mask)
{
	struct cpuset *cs;

	if (is_in_v2_mode()) {
		cs = task_cs(p);
		if (cs && cs->effective_cpus)
			new_mask = cs->effective_cpus;
	}

	return set_cpus_allowed_ptr(p, new_mask);
}

#ifdef CONFIG_SMP
static void droidspaces_partition_sched_domains(int ndoms_new,
						 cpumask_var_t doms_new[],
						 struct sched_domain_attr *dattr_new)
{
	/*
	 * cgroup v2 cpuset on this Android 4.19 vendor scheduler must not
	 * mutate scheduler domains. The generated masks are owned by this
	 * call site, so release them when the rebuild is intentionally skipped.
	 */
	if (is_in_v2_mode()) {
		if (doms_new)
			free_sched_domains(doms_new, ndoms_new);
		kfree(dattr_new);
		return;
	}

	partition_sched_domains(ndoms_new, doms_new, dattr_new);
}
#endif
