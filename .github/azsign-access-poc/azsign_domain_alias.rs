// Logical RustDesk destinations only. The socket and TLS name still come from
// the authenticated enrollment, never from the requested alias.
pub fn accepts(host: &str, enrolled_host: &str, server_name: &str) -> bool {
    if host == enrolled_host || host == server_name {
        return true;
    }
    let managed = |name: &str| matches!(name, "rustdesk.azsign.com.br" | "remote.azsign.com.br");
    managed(host) && managed(enrolled_host) && managed(server_name)
}

#[cfg(test)]
mod tests {
    use super::accepts;

    #[test]
    fn transition_accepts_both_directions_only_for_managed_profiles() {
        for enrolled in ["rustdesk.azsign.com.br", "remote.azsign.com.br"] {
            for target in ["rustdesk.azsign.com.br", "remote.azsign.com.br"] {
                assert!(accepts(target, enrolled, enrolled));
            }
            for target in ["127.0.0.1", "18.230.75.197", "rs-ny.rustdesk.com", "remote.azsign.com.br.evil.test", "evil.test"] {
                assert!(!accepts(target, enrolled, enrolled));
            }
        }
    }

    #[test]
    fn other_installations_keep_exact_matching() {
        assert!(accepts("gateway.example", "gateway.example", "tls.example"));
        assert!(accepts("tls.example", "gateway.example", "tls.example"));
        assert!(!accepts("remote.azsign.com.br", "gateway.example", "tls.example"));
        assert!(!accepts("remote.azsign.com.br", "gateway.example", "rustdesk.azsign.com.br"));
        assert!(!accepts("remote.azsign.com.br", "rustdesk.azsign.com.br", "tls.example"));
    }
}
