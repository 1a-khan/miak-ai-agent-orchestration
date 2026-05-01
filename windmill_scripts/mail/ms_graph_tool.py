import requests
import wmill
from typing import Optional, Literal, Dict, Any


GRAPH_BASE = "https://graph.microsoft.com/v1.0"


def _get_token() -> str:
    tenant_id = wmill.get_variable("u/ammad/MS_TENANT_ID")
    client_id = wmill.get_variable("u/ammad/MS_CLIENT_ID")
    client_secret = wmill.get_variable("u/ammad/MS_CLIENT_SECRET")

    token_url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"

    resp = requests.post(
        token_url,
        data={
            "client_id": client_id,
            "client_secret": client_secret,
            "scope": "https://graph.microsoft.com/.default",
            "grant_type": "client_credentials",
        },
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]



def _graph_get(
    access_token: str,
    url: str,
    params: Optional[dict] = None,
    extra_headers: Optional[dict] = None,
) -> dict:
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/json",
    }
    if extra_headers:
        headers.update(extra_headers)

    resp = requests.get(
        url,
        headers=headers,
        params=params,
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()



def _graph_post(
    access_token: str,
    url: str,
    json_body: dict,
) -> dict:
    resp = requests.post(
        url,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        json=json_body,
        timeout=60,
    )
    resp.raise_for_status()
    if resp.content:
        return resp.json()
    return {}



def _message_to_clean_json(message: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": message.get("id"),
        "subject": message.get("subject"),
        "from": (message.get("from") or {}).get("emailAddress", {}),
        "sender": (message.get("sender") or {}).get("emailAddress", {}),
        "to_recipients": [
            r.get("emailAddress", {}) for r in message.get("toRecipients", [])
        ],
        "cc_recipients": [
            r.get("emailAddress", {}) for r in message.get("ccRecipients", [])
        ],
        "received_date_time": message.get("receivedDateTime"),
        "sent_date_time": message.get("sentDateTime"),
        "is_read": message.get("isRead"),
        "importance": message.get("importance"),
        "has_attachments": message.get("hasAttachments"),
        "body_preview": message.get("bodyPreview"),
        "web_link": message.get("webLink"),
        "body": message.get("body"),
        "parent_folder_id": message.get("parentFolderId"),
    }


def _message_to_compact_json(message: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": message.get("id"),
        "subject": message.get("subject"),
        "from_address": ((message.get("from") or {}).get("emailAddress") or {}).get("address"),
        "from_name": ((message.get("from") or {}).get("emailAddress") or {}).get("name"),
        "received_date_time": message.get("receivedDateTime"),
        "sent_date_time": message.get("sentDateTime"),
        "is_read": message.get("isRead"),
        "body_preview": message.get("bodyPreview"),
    }



def _target_user() -> str:
    return wmill.get_variable("u/ammad/MS_TARGET_USER")



def main(
    action: Literal[
        "list_recent",
        "list_unread",
        "get_email",
        "search",
        "list_inbox_child_folders",
        "move_email",
        "send_email",
    ] = "list_unread",
    top: int = 10,
    email_id: Optional[str] = None,
    query: Optional[str] = None,
    destination_folder_id: Optional[str] = None,
    to_email: Optional[str] = None,
    subject: Optional[str] = None,
    body_text: Optional[str] = None,
    sender_email: Optional[str] = None,
    subject_contains: Optional[str] = None,
    unread_only: bool = False,
    compact: bool = False,
):
    access_token = _get_token()
    target_user = _target_user()

    if action == "list_recent":
        url = f"{GRAPH_BASE}/users/{target_user}/messages"
        data = _graph_get(
            access_token,
            url,
            params={
                "$top": max(top, 50) if (sender_email or subject_contains or unread_only) else top,
                "$orderby": "receivedDateTime DESC",
                "$select": ",".join([
                    "id",
                    "subject",
                    "from",
                    "sender",
                    "toRecipients",
                    "ccRecipients",
                    "receivedDateTime",
                    "sentDateTime",
                    "isRead",
                    "importance",
                    "hasAttachments",
                    "bodyPreview",
                    "webLink",
                    "parentFolderId",
                ]),
            },
        )

        messages = data.get("value", [])

        if unread_only:
            messages = [m for m in messages if m.get("isRead") is False]

        if sender_email:
            wanted = sender_email.strip().lower()
            messages = [
                m for m in messages
                if (((m.get("from") or {}).get("emailAddress") or {}).get("address", "").strip().lower() == wanted)
            ]

        if subject_contains:
            needle = subject_contains.lower()
            messages = [
                m for m in messages
                if needle in (m.get("subject") or "").lower()
            ]

        messages = messages[:top]

        formatter = _message_to_compact_json if compact else _message_to_clean_json
        return {
            "action": action,
            "count": len(messages),
            "messages": [formatter(m) for m in messages],
        }

    if action == "list_unread":
        url = f"{GRAPH_BASE}/users/{target_user}/messages"
        data = _graph_get(
            access_token,
            url,
            params={
                "$top": top,
                "$filter": "isRead eq false",
                "$orderby": "receivedDateTime DESC",
                "$select": ",".join([
                    "id",
                    "subject",
                    "from",
                    "sender",
                    "toRecipients",
                    "ccRecipients",
                    "receivedDateTime",
                    "sentDateTime",
                    "isRead",
                    "importance",
                    "hasAttachments",
                    "bodyPreview",
                    "webLink",
                    "parentFolderId",
                ]),
            },
        )
        return {
            "action": action,
            "count": len(data.get("value", [])),
            "messages": [_message_to_clean_json(m) for m in data.get("value", [])],
        }

    if action == "get_email":
        if not email_id:
            raise ValueError("email_id is required for action='get_email'")

        url = f"{GRAPH_BASE}/users/{target_user}/messages/{email_id}"
        data = _graph_get(
            access_token,
            url,
            params={
                "$select": ",".join([
                    "id",
                    "subject",
                    "from",
                    "sender",
                    "toRecipients",
                    "ccRecipients",
                    "receivedDateTime",
                    "sentDateTime",
                    "isRead",
                    "importance",
                    "hasAttachments",
                    "bodyPreview",
                    "webLink",
                    "body",
                    "parentFolderId",
                ]),
            },
        )
        return {
            "action": action,
            "message": _message_to_clean_json(data),
        }

    if action == "search":
        if not query:
            raise ValueError("query is required for action='search'")

        url = f"{GRAPH_BASE}/users/{target_user}/messages"
        data = _graph_get(
            access_token,
            url,
            params={
                "$top": top,
                "$search": f'"{query}"',
                "$select": ",".join([
                    "id",
                    "subject",
                    "from",
                    "sender",
                    "toRecipients",
                    "ccRecipients",
                    "receivedDateTime",
                    "sentDateTime",
                    "isRead",
                    "importance",
                    "hasAttachments",
                    "bodyPreview",
                    "webLink",
                    "parentFolderId",
                ]),
            },
            extra_headers={
                "ConsistencyLevel": "eventual",
            },
        )
        return {
            "action": action,
            "count": len(data.get("value", [])),
            "messages": [_message_to_clean_json(m) for m in data.get("value", [])],
        }

    if action == "list_inbox_child_folders":
        url = f"{GRAPH_BASE}/users/{target_user}/mailFolders/inbox/childFolders"
        data = _graph_get(
            access_token,
            url,
            params={
                "$top": top,
            },
        )
        return {
            "action": action,
            "count": len(data.get("value", [])),
            "folders": [
                {
                    "id": f.get("id"),
                    "display_name": f.get("displayName"),
                    "child_folder_count": f.get("childFolderCount"),
                    "unread_item_count": f.get("unreadItemCount"),
                    "total_item_count": f.get("totalItemCount"),
                }
                for f in data.get("value", [])
            ],
        }

    if action == "move_email":
        if not email_id:
            raise ValueError("email_id is required for action='move_email'")
        if not destination_folder_id:
            raise ValueError("destination_folder_id is required for action='move_email'")

        url = f"{GRAPH_BASE}/users/{target_user}/messages/{email_id}/move"
        data = _graph_post(
            access_token,
            url,
            json_body={
                "destinationId": destination_folder_id,
            },
        )
        return {
            "action": action,
            "message": _message_to_clean_json(data),
        }

    if action == "send_email":
        if not to_email:
            raise ValueError("to_email is required for action='send_email'")
        if not subject:
            raise ValueError("subject is required for action='send_email'")
        if body_text is None:
            raise ValueError("body_text is required for action='send_email'")

        url = f"{GRAPH_BASE}/users/{target_user}/sendMail"
        _graph_post(
            access_token,
            url,
            json_body={
                "message": {
                    "subject": subject,
                    "body": {
                        "contentType": "Text",
                        "content": body_text,
                    },
                    "toRecipients": [
                        {
                            "emailAddress": {
                                "address": to_email,
                            }
                        }
                    ],
                },
                "saveToSentItems": True,
            },
        )
        return {
            "action": action,
            "status": "sent",
            "to_email": to_email,
            "subject": subject,
        }

    raise ValueError(f"Unsupported action: {action}")
