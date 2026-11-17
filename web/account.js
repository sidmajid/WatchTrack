(() => {
  "use strict";
  const STATE_KEY = "watchtrack-state-v2";
  let client = null, currentUser = null, syncTimer = null, syncBusy = false, syncAgain = false;
  const $ = id => document.getElementById(id);
  const status = (message, error = false) => {
    const el = $("accountStatus");
    if (el) { el.textContent = message; el.dataset.state = error ? "error" : "success"; }
  };
  const localState = () => {
    try { return JSON.parse(localStorage.getItem(STATE_KEY) || "null") || {watchedMovies:[],tvProgress:{},wishlist:[]}; }
    catch { throw new Error("Local data could not be read. Nothing was changed."); }
  };
  const normalize = x => ({
    watchedMovies: Array.isArray(x?.watchedMovies) ? x.watchedMovies : [],
    tvProgress: x?.tvProgress && typeof x.tvProgress === "object" && !Array.isArray(x.tvProgress) ? x.tvProgress : {},
    wishlist: Array.isArray(x?.wishlist) ? x.wishlist : []
  });
  const merge = (cloud, local) => {
    if (Array.isArray(cloud) && Array.isArray(local)) {
      const m = new Map(); [...cloud,...local].forEach(x => m.set(JSON.stringify(x),x)); return [...m.values()];
    }
    if (cloud && local && typeof cloud === "object" && typeof local === "object" && !Array.isArray(cloud) && !Array.isArray(local)) {
      const out = {...cloud}; Object.entries(local).forEach(([k,v]) => out[k] = k in out ? merge(out[k],v) : v); return out;
    }
    return local === undefined ? cloud : local;
  };
  const backup = data => {
    const blob = new Blob([JSON.stringify({app:"WatchTrack",version:1,exportedAt:new Date().toISOString(),data},null,2)],{type:"application/json"});
    const url = URL.createObjectURL(blob), a = document.createElement("a");
    a.href=url; a.download="watchtrack-before-account-migration.json"; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(()=>URL.revokeObjectURL(url),1000);
  };
  const loadSdk = () => new Promise((resolve,reject) => {
    if (window.supabase?.createClient) return resolve();
    const s=document.createElement("script"); s.src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"; s.async=true;
    s.onload=()=>window.supabase?.createClient?resolve():reject(new Error("Supabase library failed to initialise."));
    s.onerror=()=>reject(new Error("Could not load account service. Check your connection.")); document.head.appendChild(s);
  });
  const render = () => {
    const signed=!!currentUser;
    if ($("accountAuthForm")) $("accountAuthForm").hidden=signed;
    if ($("accountSignedIn")) $("accountSignedIn").hidden=!signed;
    if ($("accountEmail")) $("accountEmail").textContent=currentUser?.email||"";
    document.querySelectorAll("[data-watchtrack-account-status]").forEach(e=>e.textContent=signed?"Account":"Sign in");
  };
  const init = async () => {
    await loadSdk();
    const c=window.WATCHTRACK_SUPABASE_CONFIG;
    if(!c?.url||!c?.publishableKey) throw new Error("Supabase public configuration is missing.");
    client=window.supabase.createClient(c.url,c.publishableKey,{auth:{autoRefreshToken:true,persistSession:true,detectSessionInUrl:true}});
    const {data,error}=await client.auth.getSession(); if(error) throw error;
    currentUser=data.session?.user||null;
    client.auth.onAuthStateChange((_event,session)=>{currentUser=session?.user||null;render();if(currentUser)scheduleSync();});
    render();
  };
  const handleAuth = async event => {
    event.preventDefault(); if(!client) return status("Account service is not ready. Retry shortly.",true);
    const email=$("accountEmailInput")?.value.trim(), password=$("accountPasswordInput")?.value||"", mode=event.submitter?.dataset.mode||"signin";
    if(!email||!password) return status("Enter your email and password.",true);
    if(mode==="signup"&&password.length<10) return status("Use a password with at least 10 characters.",true);
    const b=event.submitter; if(b){b.disabled=true;b.textContent="Please wait…";}
    try {
      if(mode==="signup"){
        const {data,error}=await client.auth.signUp({email,password,options:{emailRedirectTo:location.origin+"/profile.html"}});
        if(error) throw error;
        status(data.session?"Account created and signed in. Your local data is unchanged.":"Account created. Check your email to verify the address, then sign in.");
      } else {
        const {error}=await client.auth.signInWithPassword({email,password}); if(error) throw error;
        status("Signed in. Your local data has not been changed.");
      }
    } catch(e){status(e.message||"Authentication failed.",true);}
    finally{if(b){b.disabled=false;b.textContent=mode==="signup"?"Create account":"Sign in";}}
  };
  const resetPassword=async()=>{
    const email=$("accountEmailInput")?.value.trim(); if(!email)return status("Enter your email address first.",true);
    try{const {error}=await client.auth.resetPasswordForEmail(email,{redirectTo:location.origin+"/profile.html"});if(error)throw error;status("If an account exists for that address, reset instructions will be emailed.");}
    catch(e){status(e.message||"Password reset could not be requested.",true);}
  };
  const signOut=async()=>{try{const {error}=await client.auth.signOut();if(error)throw error;status("Signed out. Local data remains on this device.");}catch(e){status(e.message||"Sign out failed.",true);}};
  const migrate=async()=>{
    if(!client||!currentUser)return status("Sign in before migrating your library.",true);
    const b=$("migrateLibraryButton");if(b){b.disabled=true;b.textContent="Preparing backup…";}
    try{
      const local=normalize(localState());
      const {data:row,error}=await client.from("watchtrack_state").select("state,revision").eq("user_id",currentUser.id).maybeSingle();
      if(error)throw error;
      const cloud=normalize(row?.state);
      const counts=x=>({movies:x.watchedMovies.length,shows:Object.keys(x.tvProgress).length,wishlist:x.wishlist.length});
      const lc=counts(local),cc=counts(cloud);
      const preview="This device: "+lc.movies+" movies, "+lc.shows+" TV shows, "+lc.wishlist+" wishlist entries.\nCloud account: "+cc.movies+" movies, "+cc.shows+" TV shows, "+cc.wishlist+" wishlist entries.\n\nA backup will be downloaded. Existing local and cloud entries will be merged; the local copy will not be deleted. Continue?";
      if(!confirm(preview))return status("Migration cancelled. Nothing was changed.");
      backup(local);
      const combined=normalize(merge(cloud,local));
      const payload={user_id:currentUser.id,state:combined,schema_version:1};
      if(row){
        const {data:updated,error:writeError}=await client.from("watchtrack_state").update({state:combined,schema_version:1}).eq("user_id",currentUser.id).eq("revision",row.revision).select("revision");
        if(writeError)throw writeError;
        if(!updated?.length)throw new Error("A newer cloud update was detected. Migration paused; your local copy is unchanged.");
      } else {
        const {error:writeError}=await client.from("watchtrack_state").insert(payload);
        if(writeError)throw writeError;
      }
      localStorage.setItem(STATE_KEY,JSON.stringify(combined));
      localStorage.setItem("watchtrack-cloud-migrated:"+currentUser.id,"1");
      status("Migration completed. Your backup was downloaded and merged library saved to your account.");
    }catch(e){status(e.message||"Migration failed. Your local copy remains on this device.",true);}
    finally{if(b){b.disabled=false;b.textContent="Back up & migrate library";}}
  };
  const syncNow=async()=>{
    if(!client||!currentUser||syncBusy||localStorage.getItem("watchtrack-cloud-migrated:"+currentUser.id)!=="1"){if(syncBusy)syncAgain=true;return;} syncBusy=true;
    try{
      const local=normalize(localState());
      const {data:row,error}=await client.from("watchtrack_state").select("state,revision").eq("user_id",currentUser.id).maybeSingle();
      if(error)throw error;
      if(!row){const {error:e}=await client.from("watchtrack_state").insert({user_id:currentUser.id,state:local,schema_version:1});if(e)throw e;}
      else {
        const combined=normalize(merge(normalize(row.state),local));
        const {data,error:e}=await client.from("watchtrack_state").update({state:combined,schema_version:1}).eq("user_id",currentUser.id).eq("revision",row.revision).select("revision");
        if(e)throw e;
        if(!data?.length)throw new Error("A newer cloud update was detected. Sync paused to avoid overwriting it.");
      }
    }catch(e){console.warn("WatchTrack sync paused:",e.message);status("Cloud sync needs attention. Local changes remain saved on this device.",true);}
    finally{syncBusy=false;if(syncAgain){syncAgain=false;scheduleSync();}}
  };
  const scheduleSync=()=>{if(!currentUser)return;clearTimeout(syncTimer);syncTimer=setTimeout(syncNow,1800);};
  window.watchTrackCloudSync=scheduleSync;
  document.addEventListener("DOMContentLoaded",()=>{
    $("accountAuthForm")?.addEventListener("submit",handleAuth);
    $("accountResetPassword")?.addEventListener("click",resetPassword);
    $("accountSignOut")?.addEventListener("click",signOut);
    $("migrateLibraryButton")?.addEventListener("click",migrate);
    init().catch(e=>status(e.message||"Account service unavailable.",true));
  });
})();
