// Datapath of the per-node shared egress HTB tree (see ../AGENTS.md).
//
// Two tcx_ingress programs implement a veth-trampoline detour that shapes a
// kura pod's egress in a shared per-node HTB tree without skipping any of
// Cilium's datapath:
//
//   kura_shaper_out — attached FIRST (mprog anchor: head) on the pod's
//     host-side veth (lxc*), before cil_from_container. Stamps
//     skb->priority with the tenant's HTB classid (HTB classifies by
//     priority natively, so the tree device needs no filters), records the
//     lxc ifindex in skb->mark, arms a tc_index loop guard, and redirects
//     the packet to the trampoline device that carries the HTB tree.
//
//   kura_shaper_ret — attached on the trampoline's peer. After HTB has
//     paced the packet across the veth, this sends it back to the recorded
//     lxc's *ingress* hook (BPF_F_INGRESS). That re-entry is a plain
//     netif_receive with no skip flags, so the whole tcx chain runs again:
//     the loop guard disarms and falls through to cil_from_container, and
//     Cilium applies policy/identity/forwarding exactly as for an unshaped
//     packet.
//
// Why the trampoline instead of the classic ifb detour: ifb re-injects with
// tc_skip_classify set, which the kernel honours for the whole tcx hook, so
// shaped packets would bypass cil_from_container entirely. Lab-verified on
// Cilium 1.18 (TCX attach, BPF host routing): the ifb form voids both the
// source pod's egress NetworkPolicy and destination ingress NetworkPolicies
// (shaped traffic re-enters via the host stack with the trusted host
// identity); the trampoline form keeps both enforced.
//
// skb fields used and why they are safe here:
//   priority — scrubbed by the kernel on every netns crossing, which is why
//     the tag cannot come from inside the pod; between this program and the
//     HTB tree the packet never crosses a netns (the trampoline veth pair
//     has both ends in the host netns), so the stamp survives.
//   mark     — Cilium owns the mark, but only from cil_from_container
//     onwards; on the detour Cilium has not run yet, and the return program
//     clears it before handing the packet back.
//   tc_index — used by nothing else on this datapath (dsmark is dead);
//     survives qdiscs and same-netns veth forwarding.
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>

#define TCX_NEXT (-1)
#define TCX_DROP 2
#define BPF_F_INGRESS_FLAG 1ULL
#define TC_INDEX_SHAPED 0x7457

enum counter {
	COUNTER_REDIRECTED = 0,
	COUNTER_GUARD_PASS = 1,
	COUNTER_SIBLING_BYPASS = 2,
	COUNTER_RETURNED = 3,
	COUNTER_RETURN_DROPPED = 4,
};

enum config_key {
	CONFIG_TRAMPOLINE_IFINDEX = 0,
	CONFIG_CLASSID = 1,
	CONFIG_SELF_IFINDEX = 2,
};

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 8);
	__type(key, __u32);
	__type(value, __u64);
} counters SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 4);
	__type(key, __u32);
	__type(value, __u32);
} config SEC(".maps");

// Co-located same-account pod IPs (IPv4, network byte order). Traffic to a
// sibling is node-local replication sync at memory speed; it must not consume
// the tenant bucket nor serialize through the trampoline. Fail-safe polarity:
// a stale entry briefly shapes sibling traffic, never unshapes tenant traffic.
struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 16);
	__type(key, __u32);
	__type(value, __u8);
} siblings SEC(".maps");

static __always_inline void bump(__u32 idx)
{
	__u64 *value = bpf_map_lookup_elem(&counters, &idx);
	if (value)
		__sync_fetch_and_add(value, 1);
}

static __always_inline __u32 config_get(__u32 key)
{
	__u32 *value = bpf_map_lookup_elem(&config, &key);
	return value ? *value : 0;
}

SEC("tcx/ingress")
int kura_shaper_out(struct __sk_buff *skb)
{
	if (skb->tc_index == TC_INDEX_SHAPED) {
		skb->tc_index = 0;
		bump(COUNTER_GUARD_PASS);
		return TCX_NEXT;
	}

	void *data = (void *)(long)skb->data;
	void *data_end = (void *)(long)skb->data_end;
	if (data + 14 + 20 <= data_end) {
		__u16 *h_proto = data + 12;
		if (*h_proto == __builtin_bswap16(0x0800)) {
			__u32 *daddr = data + 14 + 16;
			if (bpf_map_lookup_elem(&siblings, daddr)) {
				bump(COUNTER_SIBLING_BYPASS);
				return TCX_NEXT;
			}
		}
	}

	__u32 trampoline = config_get(CONFIG_TRAMPOLINE_IFINDEX);
	__u32 classid = config_get(CONFIG_CLASSID);
	__u32 self = config_get(CONFIG_SELF_IFINDEX);
	if (!trampoline || !classid || !self)
		// Unconfigured: never blackhole, fall through to Cilium unshaped.
		return TCX_NEXT;

	skb->priority = classid;
	skb->mark = self;
	skb->tc_index = TC_INDEX_SHAPED;
	bump(COUNTER_REDIRECTED);
	return bpf_redirect(trampoline, 0);
}

SEC("tcx/ingress")
int kura_shaper_ret(struct __sk_buff *skb)
{
	__u32 target = skb->mark;

	if (!target || skb->tc_index != TC_INDEX_SHAPED) {
		// Nothing legitimate transmits on the trampoline besides shaped
		// pod packets; anything else (stray host-stack noise) is dropped
		// and counted rather than forwarded somewhere half-processed.
		bump(COUNTER_RETURN_DROPPED);
		return TCX_DROP;
	}
	skb->mark = 0;
	bump(COUNTER_RETURNED);
	return bpf_redirect(target, BPF_F_INGRESS_FLAG);
}
