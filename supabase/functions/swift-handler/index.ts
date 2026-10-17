import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

class HttpError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const triageIncident = (description: string) => {
  const text = description.toLowerCase();

  if (
    text.includes("murder") ||
    text.includes("fire") ||
    text.includes("kill") ||
    text.includes("dying") ||
    text.includes("terror")
  ) {
    return { priority: "Critical", category: "Violent Crime/Emergency" };
  }

  if (
    text.includes("robbery") ||
    text.includes("gun") ||
    text.includes("accident") ||
    text.includes("rape") ||
    text.includes("defilement") ||
    text.includes("kidnap")
  ) {
    return { priority: "High", category: "Major Incident" };
  }

  if (
    text.includes("theft") ||
    text.includes("stolen") ||
    text.includes("domestic") ||
    text.includes("fraud") ||
    text.includes("assault")
  ) {
    return { priority: "Medium", category: "General Crime" };
  }

  return { priority: "Low", category: "General/Inquiry" };
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  try {
    const authorization = req.headers.get("Authorization");
    const accessToken = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!accessToken) throw new HttpError("Authentication required.", 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      throw new Error("Required Supabase function environment variables are missing.");
    }

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const {
      data: { user },
      error: authError,
    } = await callerClient.auth.getUser(accessToken);
    if (authError || !user) {
      throw new HttpError("Invalid or expired access token.", 401);
    }

    const body = await req.json();
    const action = body?.action;

    if (action === "create-admin") {
      const {
        email,
        password,
        first_name: firstName,
        last_name: lastName,
        role,
        station_id: stationId,
      } = body;

      if (
        typeof email !== "string" ||
        typeof password !== "string" ||
        typeof firstName !== "string" ||
        typeof lastName !== "string" ||
        typeof role !== "string"
      ) {
        throw new HttpError("Invalid account details.", 400);
      }

      const { data, error } = await callerClient.rpc("admin_create_user", {
        new_email: email,
        new_password: password,
        new_first_name: firstName,
        new_last_name: lastName,
        new_role: role,
        new_station_id: stationId ?? null,
      });
      if (error) throw new HttpError(error.message, 403);

      return jsonResponse({ success: true, user_id: data });
    }

    if (action === "triage-incident") {
      const incidentId = body?.incident_id;
      if (typeof incidentId !== "string") {
        throw new HttpError("A valid incident ID is required.", 400);
      }

      const { data: profile, error: profileError } = await callerClient
        .from("user_profiles")
        .select("role, account_status")
        .eq("user_id", user.id)
        .maybeSingle();
      if (profileError) throw profileError;
      if (!profile || profile.account_status !== "active") {
        throw new HttpError("Active account required.", 403);
      }

      const { data: incident, error: incidentError } = await callerClient
        .from("incidents")
        .select("id, user_id, description")
        .eq("id", incidentId)
        .maybeSingle();
      if (incidentError) throw incidentError;
      if (!incident) {
        throw new HttpError("Incident not found or access denied.", 404);
      }

      const isOwner = incident.user_id === user.id;
      const isPoliceStaff = [
        "system_admin",
        "central_admin",
        "station_admin",
        "field_officer",
      ].includes(profile.role);
      if (!isOwner && !isPoliceStaff) {
        throw new HttpError("Access denied.", 403);
      }

      const analysis = triageIncident(incident.description);
      const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
        auth: { autoRefreshToken: false, persistSession: false },
      });
      const { error: updateError } = await serviceClient
        .from("incidents")
        .update({
          priority: analysis.priority,
          ai_analysis_summary:
            `Agent classified as ${analysis.category} based on keywords.`,
        })
        .eq("id", incident.id);
      if (updateError) throw updateError;

      return jsonResponse({
        success: true,
        priority: analysis.priority,
        category: analysis.category,
      });
    }

    throw new HttpError("Invalid action type.", 400);
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }

    console.error("swift-handler failed:", error);
    return jsonResponse({ error: "The request could not be completed." }, 500);
  }
});
