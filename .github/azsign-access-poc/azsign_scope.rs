//! Scope supplied by the authenticated relay, not by the remote operator.
use crate::{anyhow::{bail, Context}, ResultType, Stream};
use serde_derive::Deserialize;

#[derive(Clone, Copy, Debug, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Scope { RemoteControl, FileTransfer }

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Prelude { schema: String, session_uuid: String, connection_type: Scope }

tokio::task_local! { pub static AUTHORIZED_SCOPE: Scope; }

fn parse(bytes: &[u8], session: &str) -> ResultType<Scope> {
    if bytes.len() > 512 { bail!("Oversized relay scope"); }
    let p: Prelude = serde_json::from_slice(bytes)?;
    if p.schema != "azsign-relay-scope-v1" || p.session_uuid != session {
        bail!("Relay scope binding mismatch");
    }
    Ok(p.connection_type)
}

pub async fn receive(stream: &mut Stream, session: &str) -> ResultType<Scope> {
    let bytes = crate::timeout(8000, stream.next()).await?
        .context("Missing authenticated relay scope")??;
    parse(&bytes, session)
}

pub fn allows_login(kind: &str) -> bool {
    AUTHORIZED_SCOPE.try_with(|scope| matches!((scope, kind),
        (Scope::RemoteControl, "remote") | (Scope::FileTransfer, "file_transfer"))).unwrap_or(false)
}

pub fn allows_files() -> bool {
    AUTHORIZED_SCOPE.try_with(|scope| *scope == Scope::FileTransfer).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_missing_mismatched_unknown_and_oversized_scope() {
        let frame = |kind: &str| format!(r#"{{"schema":"azsign-relay-scope-v1","session_uuid":"session","connection_type":"{kind}"}}"#);
        assert_eq!(parse(frame("file_transfer").as_bytes(), "session").unwrap(), Scope::FileTransfer);
        assert_eq!(parse(frame("remote_control").as_bytes(), "session").unwrap(), Scope::RemoteControl);
        assert!(parse(frame("file_transfer").as_bytes(), "other").is_err());
        assert!(parse(frame("port_forward").as_bytes(), "session").is_err());
        assert!(parse(b"{}", "session").is_err());
        assert!(parse(&vec![0; 513], "session").is_err());
        assert!(!allows_login("remote"));
        assert!(!allows_files());
    }

    #[tokio::test]
    async fn scope_is_task_local_and_cannot_escalate_between_connections() {
        let remote = AUTHORIZED_SCOPE.scope(Scope::RemoteControl, async {
            tokio::task::yield_now().await;
            assert!(allows_login("remote"));
            assert!(!allows_login("file_transfer"));
            assert!(!allows_files());
            assert!(!allows_login("terminal"));
        });
        let files = AUTHORIZED_SCOPE.scope(Scope::FileTransfer, async {
            tokio::task::yield_now().await;
            assert!(allows_login("file_transfer"));
            assert!(allows_files());
            assert!(!allows_login("remote"));
        });
        tokio::join!(remote, files);
        assert!(!allows_files());
    }
}
