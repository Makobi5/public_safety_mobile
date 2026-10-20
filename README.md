# Community SafeWatch: Public Safety Reporting App (PSRA)

**Community SafeWatch** is a mobile-first Flutter application designed to bridge the communication gap between citizens and law enforcement. Using a case study of the **Kabale Central Police Unit** in Uganda, this app allows citizens to report incidents in real-time with GPS coordinates and multimedia evidence, while providing police commanders (OCs) with a high-tech Control Center to triage and manage cases.

## 🚀 Key Features

### 👤 For Community Members (Users)
*   **Multi-Step Reporting:** A simplified 3-step process to report crimes or safety concerns.
*   **GPS Accuracy:** Automatic location capture using device hardware to ensure responders know exactly where to go.
*   **Multimedia Evidence:** Attach photos, videos, or audio directly from the camera or gallery.
*   **Two-Way Feedback:** Receive live updates on case status (e.g., "Under Investigation", "Action Taken") and read official officer notes.
*   **Real-time Notifications:** In-app visual indicators (red dots and badges) signal when the police have provided feedback.
*   **Data Portability:** Download and save submitted evidence back to the local device for legal records.

### 👮 For Police Administration
*   **Safety Control Center:** A professional dashboard showing real-time statistics on active cases, critical incidents, and response rates.
*   **AI Triage Agent:** A Supabase Edge Function (`swift-handler`) that automatically analyzes descriptions and flags life-threatening cases (e.g., Murder, Fire) as **CRITICAL**.
*   **User and Station Management:** System Admins manage all staff and CPS assignments; Central Admins manage stations and staff under their assigned CPS; Station Admins manage Field Officers at their station.
*   **Unique Officers in Charge:** A database constraint allows at most one Central Admin per CPS and one Station Admin per police station.
*   **Searchable Staff Assignment:** Staff creation supports searching eligible CPS and police stations by name or district.
*   **Station OCs:** System Admins and Central Admins can assign or clear a station's OC from its active Station Admins and Field Officers.
*   **Station Search:** Station Management supports searching stations by name, district, type, or OC.
*   **Scoped Case Access:** Central Admins see cases for their CPS and child stations; Station Admins and Field Officers are limited to cases assigned to their station.
*   **Editable Station Hierarchy:** CPS-to-station relationships are stored in Supabase and can be reassigned by System Admins without importing or hard-coding the PDF directory.
*   **Evidence Viewer:** Interactive image gallery with pinch-to-zoom and download capabilities for forensic review.

### Supabase role-hierarchy migration
Before using the updated staff creation flow, deploy the updated
`swift-handler` with `supabase functions deploy swift-handler`. It creates
accounts through the Supabase Auth Admin API and verifies the caller's role
assignment permission. Apply these migrations in order in the Supabase SQL
Editor:

[`supabase/migrations/20261017000000_admin_hierarchy.sql`](./supabase/migrations/20261017000000_admin_hierarchy.sql)
[`supabase/migrations/20261019000000_station_oc_management.sql`](./supabase/migrations/20261019000000_station_oc_management.sql)
[`supabase/migrations/20261020000000_staff_auth_and_oc_uniqueness.sql`](./supabase/migrations/20261020000000_staff_auth_and_oc_uniqueness.sql).

The latest migration disables the legacy SQL-based Auth user creation function
and enforces one Central Admin per CPS and one Station Admin per station. Update
the app after the function is deployed and before applying that migration. The
migrations preserve existing station rows,
rename existing `super_admin` accounts to `system_admin`, and map existing
`admin` accounts to unassigned `station_admin` accounts. System Admins must
then mark the appropriate existing station records as CPS entries and assign
child stations to them. Existing stations such as Kisubi are retained; the
directory PDF is not used to assign command boundaries. The follow-up migration
adds scoped station-OC assignment and updates the station-edit policy.
The latest migration will stop if duplicate OCs are already assigned; resolve
those duplicate role assignments before applying it. Check for conflicts with:

```sql
select ps.name, ps.station_type, string_agg(up.role, ', ') as roles,
       count(*) as assigned_count
from public.user_profiles as up
join public.police_stations as ps on ps.id = up.assigned_station_id
where up.role in ('central_admin', 'station_admin')
group by ps.id, ps.name, ps.station_type
having count(*) > 1;
```

Staff accounts created by the legacy SQL-based function that fail to sign in
should be deleted and recreated after the updated Edge Function is deployed.

## 🛠️ Tech Stack
*   **Frontend:** Flutter (Mobile-First, Web Compatible)
*   **Backend:** Supabase (PostgreSQL, Auth, Storage)
*   **Logic:** Supabase Edge Functions (TypeScript/Deno) & Database RPCs (PL/pgSQL)
*   **Location:** Geolocator & Geocoding API
*   **State Management:** Stateful UI with Real-time Postgres Listeners

## 🌍 Geographical Scope (Uganda)
The app uses a strict 4-level administrative hierarchy tailored to Uganda:
1.  **Region** (Western, Central, Eastern, Northern)
2.  **District** (e.g., Kabale, Kampala, Mbarara)
3.  **Sub-County / Division** (e.g., Central Division, Kyanamira)
4.  **Village / Cell / Area** (User-defined specific details)

## 📦 Setup & Installation

### 1. Environment Variables
Create a `.env` file in the root directory and add your Supabase credentials:
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
