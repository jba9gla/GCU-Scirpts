<?php
/*
 * SNIPPET NAME: RailView - v1.42 (Enhanced SEO & Performance) - DEBUGGED
 * VERSION: 1.42-fixed
 * DESCRIPTION: Bug fixes for undefined variables and selector mismatches
 * FIXES: Added currentTrains initialization, fixed button selector, cleaned up CSS
 */

if ( ! class_exists( 'RailView_v1_42' ) ) {

    class RailView_v1_42 {

        public function __construct() {
            add_action('admin_menu', [$this, 'add_admin_menu']);
            add_action('admin_init', [$this, 'register_settings']);
            add_action('rest_api_init', [$this, 'register_api_routes']);
            add_action('wp_head', [$this, 'inject_seo_and_pwa']);
            add_shortcode('rail_map_system', [$this, 'render_shortcode']);
        }

        /* --- 1. SETTINGS --- */
        public function add_admin_menu() {
            add_menu_page('RailView Config', 'RailView Config', 'manage_options', 'rail-map-config', [$this, 'settings_page_html'], 'dashicons-train');
        }

        public function register_settings() {
            register_setting('rail_map_options', 'rm_nr_key');
            register_setting('rail_map_options', 'rm_mapbox_key');
            register_setting('rail_map_options', 'rm_here_key');
            register_setting('rail_map_options', 'rm_logo_url');
            register_setting('rail_map_options', 'rm_broadcast_msg');
            register_setting('rail_map_options', 'rm_sim_mode');
            register_setting('rail_map_options', 'rm_hide_header');
        }

        public function settings_page_html() {
            ?>
            <div class="wrap">
                <h1>RailView Configuration (v1.42)</h1>
                <form method="post" action="options.php">
                    <?php settings_fields('rail_map_options'); ?>
                    <?php do_settings_sections('rail_map_options'); ?>
                    <table class="form-table">
                        <tr><th>National Rail Token</th><td><input type="text" name="rm_nr_key" value="<?php echo esc_attr(get_option('rm_nr_key')); ?>" class="regular-text" /></td></tr>
                        <tr><th>Mapbox Token</th><td><input type="text" name="rm_mapbox_key" value="<?php echo esc_attr(get_option('rm_mapbox_key')); ?>" class="regular-text" /></td></tr>
                        <tr><th>HERE Maps Key</th><td><input type="text" name="rm_here_key" value="<?php echo esc_attr(get_option('rm_here_key')); ?>" class="regular-text" /></td></tr>
                        <tr><th>Broadcast Message</th><td><textarea name="rm_broadcast_msg" rows="2" class="large-text"><?php echo esc_textarea(get_option('rm_broadcast_msg')); ?></textarea></td></tr>
                        <tr><th>Logo URL</th><td><input type="text" name="rm_logo_url" value="<?php echo esc_attr(get_option('rm_logo_url')); ?>" class="large-text" /></td></tr>
                        <tr><th>Hide Theme Header</th><td><label><input type="checkbox" name="rm_hide_header" value="1" <?php checked(1, get_option('rm_hide_header'), true); ?> /> Yes (Force Full Screen)</label></td></tr>
                    </table>
                    <?php submit_button(); ?>
                </form>
            </div>
            <?php
        }

        /* --- 2. API & PWA & SEO --- */
        public function inject_seo_and_pwa() {
            $manifest = get_rest_url(null, 'railmap/v1/manifest');
            $logo = get_option('rm_logo_url') ?: 'https://via.placeholder.com/192.png?text=RailApp';
            
            echo '<link rel="manifest" href="' . esc_url($manifest) . '">';
            echo '<meta name="theme-color" content="#0b0c0c">';
            echo '<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">';
            
            // SEO Structured Data
            ?>
            <script type="application/ld+json">
            {
              "@context": "https://schema.org",
              "@type": "WebApplication",
              "name": "RailView Scotland",
              "url": "<?php echo esc_url(home_url()); ?>",
              "applicationCategory": "TravelApplication",
              "operatingSystem": "All",
              "description": "Live interactive train map for Scotland. Track departures for Ayrshire, North Clyde and the Glasgow Subway.",
              "browserRequirements": "Requires JavaScript and Leaflet support.",
              "image": "<?php echo esc_url($logo); ?>"
            }
            </script>
            <?php
        }

        public function register_api_routes() {
            register_rest_route('railmap/v1', '/live/(?P<st>[a-zA-Z0-9-]+)', ['methods' => 'GET', 'callback' => [$this, 'fetch_live_data'], 'permission_callback' => '__return_true']);
            register_rest_route('railmap/v1', '/manifest', ['methods' => 'GET', 'callback' => [$this, 'serve_manifest'], 'permission_callback' => '__return_true']);
            register_rest_route('railmap/v1', '/contact', ['methods' => 'POST', 'callback' => [$this, 'handle_contact_form'], 'permission_callback' => '__return_true']);
        }

        public function serve_manifest() {
            $logo = get_option('rm_logo_url') ?: 'https://via.placeholder.com/192.png?text=RailApp';
            return ["name"=>"RailView","short_name"=>"RailView","start_url"=>home_url(),"display"=>"standalone","background_color"=>"#f3f2f1","theme_color"=>"#0b0c0c","icons"=>[["src"=>$logo,"sizes"=>"192x192","type"=>"image/png"]]];
        }

        public function handle_contact_form($request) {
            $params = $request->get_params();
            
            // Security Checks
            if (!empty($params['website_check'])) return new WP_Error('spam', 'Spam detected', ['status' => 403]);
            if (isset($params['math_answer']) && $params['math_answer'] != '4') return new WP_Error('math_fail', 'Incorrect math answer', ['status' => 400]);

            $msg = sanitize_textarea_field($params['message']);
            $email = sanitize_email($params['email']);
            
            if (empty($msg) || empty($email)) return new WP_Error('missing', 'Fill all fields', ['status' => 400]);
            
            wp_mail(get_option('admin_email'), "RailView Feedback", "From: $email\n\n$msg");
            return ['success' => true];
        }

        public function fetch_live_data($data) {
            $token = get_option('rm_nr_key');
            $st = strtoupper($data['st']);
            $sim = get_option('rm_sim_mode');

            if ($sim) return ['trainServices' => [['std'=>date('H:i',strtotime('+5m')), 'etd'=>'On time', 'operator'=>'ScotRail', 'platform'=>'1', 'origin'=>[['locationName'=>'Sim Origin']], 'destination'=>[['locationName'=>'Sim Dest']], 'subsequentCallingPoints'=>[]]]];
            
            if ($st === 'SUBWAY') {
                return ['trainServices' => [
                    ['std'=>'Every 4m', 'etd'=>'On Time', 'operator'=>'SPT', 'platform'=>'Inner', 'destination'=>[['locationName'=>'Inner Circle']]],
                    ['std'=>'Every 4m', 'etd'=>'On Time', 'operator'=>'SPT', 'platform'=>'Outer', 'destination'=>[['locationName'=>'Outer Circle']]]
                ]];
            }

            if (empty($token)) return new WP_Error('no_key', 'Missing Token', ['status' => 401]);

            // Caching with Transients (60 second cache)
            $cache_key = 'rail_live_' . $st;
            $cached_data = get_transient($cache_key);
            if ($cached_data !== false) return $cached_data;

            $url = "https://huxley2.azurewebsites.net/departures/{$st}/40?expand=true&accessToken=" . $token;
            $res = wp_remote_get($url, ['timeout' => 15]);
            
            if (is_wp_error($res)) return new WP_Error('api_fail', 'Error contacting rail server', ['status' => 500]);
            
            $json = json_decode(wp_remote_retrieve_body($res));
            if (!isset($json->trainServices)) return ['trainServices' => []];

            $filtered = [];
            foreach($json->trainServices as $t) {
                $dest = isset($t->destination[0]->crs) ? $t->destination[0]->crs : '';
                if ($dest !== $st) $filtered[] = $t;
            }
            
            $output = ['trainServices' => $filtered];
            set_transient($cache_key, $output, 60);
            
            return $output;
        }

        /* --- 3. FRONTEND RENDER --- */
        public function render_shortcode() {
            wp_enqueue_style('leaflet-css', 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css');
            wp_enqueue_script('leaflet-js', 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js', [], null, true);
            
            $api = esc_url_raw(get_rest_url(null, 'railmap/v1/'));
            $logo = get_option('rm_logo_url');
            $broadcast = get_option('rm_broadcast_msg');
            $mapbox_key = get_option('rm_mapbox_key');
            $here_key = get_option('rm_here_key');
            
            $styles = $this->get_app_css();

            ob_start();
            ?>
            
            <style><?php echo $styles; ?></style>

            <div id="rail-app-breakout">
                <div id="rail-map" aria-label="Train Map" role="application"></div>
                <div id="drag-handle" title="Resize Panel"></div>
                <div id="rail-panel" role="region" aria-label="Information Panel">
                    <?php if($broadcast): ?><div style="background:#1d70b8;color:#fff;padding:12px;font-weight:bold;text-align:center;"><?php echo esc_html($broadcast); ?></div><?php endif; ?>
                    
                    <div class="panel-header">
                        <div class="ph-left">
                            <?php if($logo): ?><img src="<?php echo esc_url($logo); ?>" class="rail-logo" alt="RailView Logo"><?php endif; ?>
                            <span class="app-title">RailView</span>
                        </div>
                        <div class="header-tools">
                            <button class="ht-btn" onclick="toggleHighContrast()" title="Toggle High Contrast" aria-label="Toggle High Contrast Mode">👁️</button>
                            <button class="ht-btn" onclick="resetMap()" aria-label="Reset Map Application">Reset</button>
                        </div>
                    </div>

                    <div class="line-controls" role="group" aria-label="Railway Line Selectors">
                        <button class="line-btn lb-all active" onclick="switchLine('all')">All</button>
                        <button class="line-btn lb-ayr" onclick="switchLine('ayrshire')">Ayrshire</button>
                        <button class="line-btn lb-nor" onclick="switchLine('northclyde')">N. Clyde</button>
                        <button class="line-btn lb-gou" onclick="switchLine('gourock')">Gourock</button>
                        <button class="line-btn lb-wem" onclick="switchLine('wemyssbay')">Wemyss Bay</button>
                        <button class="line-btn lb-pai" onclick="switchLine('paisley')">Paisley Canal</button>
                        <button class="line-btn lb-ek" onclick="switchLine('ek')">E. Kilbride</button>
                        <button class="line-btn lb-bar" onclick="switchLine('barrhead')">Barrhead</button>
                        <button class="line-btn lb-sub" onclick="switchLine('subway')">Subway</button>
                    </div>

                    <div id="beta-banner" class="phase-banner">
                        <span class="phase-tag">BETA</span>
                        <span>This line is in testing. Data may be incomplete.</span>
                    </div>

                    <div class="planner-form">
                        <label for="station-input" class="screen-reader-text">Search Station</label>
                        <div class="autocomplete-wrapper">
                            <input type="text" id="station-input" class="st-input" placeholder="Start typing station name..." autocomplete="off" aria-expanded="false" aria-owns="autocomplete-list" aria-autocomplete="list">
                            <ul id="autocomplete-list" class="autocomplete-items" role="listbox"></ul>
                        </div>
                    </div>

                    <div id="station-tabs" role="tablist">
                        <div style="display:flex;">
                            <button class="tab-btn active" id="tab-live-btn" onclick="switchTab('live')" role="tab" aria-selected="true" aria-controls="tab-content-live">Live Board</button>
                            <button class="tab-btn" id="tab-time-btn" onclick="switchTab('time')" role="tab" aria-selected="false" aria-controls="tab-content-time">Timetable</button>
                            <button class="tab-btn" id="tab-help-btn" onclick="switchTab('help')" role="tab" aria-selected="false" aria-controls="tab-content-help">Help</button>
                        </div>
                    </div>

                    <div id="station-header-container">
                        <h2 class="station-heading" id="station-header-text">Station Name</h2>
                        <span class="station-caption">Live Departures</span>
                    </div>

                    <div id="tab-content-live" role="tabpanel">
                        <div id="largs-warning" class="warning-box">⚠️ Data may be incorrect. Visit <a href="https://scotrail.co.uk" target="_blank">scotrail.co.uk</a>.</div>
                        <div id="spt-warning" class="warning-box spt-box">🚇 Live Subway data unavailable. Visit <a href="https://www.spt.co.uk/travel-with-spt/subway/" target="_blank">spt.co.uk</a>.</div>
                        
                        <div id="largs-ferry-box" style="display:none; padding:15px; text-align:center;">
                            <a href="https://www.calmac.co.uk/service-status?route=20" target="_blank" class="gov-action-btn" style="background:#005eb8;">Ferry to Cumbrae (Beta)</a>
                        </div>

                        <div id="tourist-info" class="tourist-box">
                            <span class="tourist-title">Sightseeing (approx 1km walk)</span>
                            <span id="tourist-text">Loading...</span>
                        </div>

                        <div id="live-list" aria-live="polite">
                            <div style="padding:60px 40px; text-align:center; color:#505a5f;">
                                <span style="font-size:30px; display:block; margin-bottom:10px;">🗺️</span>
                                <strong>Select a station</strong> to view live trains.
                            </div>
                        </div>
                        <button id="show-more-btn" class="load-more-btn hidden" onclick="showNextBatch()">Show More Trains</button>
                    </div>

                    <div id="tab-content-time" style="display:none;" role="tabpanel">
                        <h3 style="padding:20px;">Future Timetables</h3>
                        <p style="padding:0 20px;">Select a date to view the full schedule on National Rail.</p>
                        <div style="padding:0 20px;">
                            <input type="date" id="tt-date" class="st-input" value="<?php echo date('Y-m-d'); ?>">
                            <button class="gov-action-btn" style="margin-top:20px;" onclick="openTimetable()">View Full Timetable ↗</button>
                        </div>
                    </div>

                    <div id="tab-content-help" style="display:none;" role="tabpanel">
                        <div style="padding:20px;">
                            <h3>Help & Support</h3>
                            <p><strong>Instructions:</strong> Select a line, then click a station pin to view live departures.</p>
                            <hr style="margin:20px 0; border:0; border-top:1px solid #ccc;">
                            <h3>Contact Us</h3>
                            <div id="contact-msg"></div>
                            
                            <label for="c-email" style="font-weight:bold; display:block; margin-top:10px;">Your Email</label>
                            <input type="email" id="c-email" class="contact-input" placeholder="name@example.com">
                            
                            <label for="c-msg" style="font-weight:bold; display:block; margin-top:10px;">Message</label>
                            <textarea id="c-msg" class="contact-area" rows="4"></textarea>
                            
                            <label for="c-math" style="font-weight:bold; display:block; margin-top:10px;">Anti-Spam: What is 2 + 2?</label>
                            <input type="number" id="c-math" class="contact-input" style="width:80px;">

                            <input type="text" id="c-check" style="display:none;" aria-hidden="true">
                            <button class="gov-action-btn" id="contact-submit-btn" style="margin-top:15px; margin-bottom: 20px;" onclick="sendContact()">Send Feedback</button>
                        </div>
                    </div>

                    <div id="fixed-facilities-container">
                        <a href="#" target="_blank" id="station-facilities-link" class="gov-action-btn">View Station Facilities ↗</a>
                    </div>
                </div>
            </div>

            <script>
                const apiRoot = "<?php echo $api; ?>";
                const mapboxKey = "<?php echo $mapbox_key; ?>";
                const hereKey = "<?php echo $here_key; ?>";
                let map, currentLayer;
                let activeLine = 'all';
                let selectedCRS = '';
                let countdownInterval;
                let currentTrains = [];
                let visibleCount = 0;

                const brLogo = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA1MCA1MCI+PHBhdGggZD0iTTAgMGg1MHY1MEgwVjB6IiBmaWxsPSIjZmZmIiBzdHJva2U9IiMwMDAiIHN0cm9rZS13aWR0aD0iMyIvPjxwYXRoIGQ9Ik0xMS41IDI1bDEzLjUgNy44VjIyaDExLjVMMjMuNSAxNy4ybC0xMy41IDcuOHptMjcuNSAwbC0xMy41LTcuOFYyOGgtMTEuNWwxMy41IDQuOCAxMy41LTcuOHoiIGZpbGw9IiMwMDAiLz48L3N2Zz4=";

                const opLinks = { "ScotRail": "https://www.scotrail.co.uk", "Avanti West Coast": "https://www.avantiwestcoast.co.uk", "LNER": "https://www.lner.co.uk", "CrossCountry": "https://www.crosscountrytrains.co.uk", "TransPennine Express": "https://www.tpexpress.co.uk", "Caledonian Sleeper": "https://www.sleeper.scot", "SPT": "https://www.spt.co.uk" };

                const touristTips = {
                    "GLC": "Gallery of Modern Art & The Lighthouse",
                    "GLQ": "George Square & City Chambers",
                    "PYG": "Paisley Abbey & Coats Observatory",
                    "LAR": "Vikingar! Experience & Largs Promenade",
                    "AYR": "Ayr Beach & Gaiety Theatre",
                    "GRK": "Gourock Outdoor Pool & Kempock St Shops",
                    "WMS": "Wemyss Bay Station Architecture & Ferry Terminal",
                    "PZW": "Burrell Collection (Pollok Park)",
                    "PTK": "Riverside Transport Museum",
                    "SUBWAY": "Kelvingrove Museum (Kelvinhall) or Botanic Gardens (Hillhead)"
                };

                const lines = {
                    ayrshire: { color: '#1d70b8', pinClass: 'pin-ayr', stations: [{n:"Glasgow Central",c:"GLC",lat:55.8580,lng:-4.2580},{n:"Paisley Gilmour St",c:"PYG",lat:55.8460,lng:-4.4280},{n:"Johnstone",c:"JHN",lat:55.8320,lng:-4.5050},{n:"Milliken Park",c:"MKP",lat:55.8230,lng:-4.5200},{n:"Howwood",c:"HOZ",lat:55.8100,lng:-4.5600},{n:"Lochwinnoch",c:"LHW",lat:55.7890,lng:-4.6220},{n:"Glengarnock",c:"GLG",lat:55.7280,lng:-4.6850},{n:"Dalry",c:"DLY",lat:55.7060,lng:-4.7200},{n:"Kilwinning",c:"KWN",lat:55.6560,lng:-4.6980},{n:"Stevenston",c:"STV",lat:55.6360,lng:-4.7550},{n:"Saltcoats",c:"SLT",lat:55.6335,lng:-4.7845},{n:"Ardrossan South Beach",c:"ASB",lat:55.6428,lng:-4.8058},{n:"West Kilbride",c:"WKB",lat:55.6953,lng:-4.8555},{n:"Fairlie",c:"FRL",lat:55.7600,lng:-4.8560},{n:"Largs",c:"LAR",lat:55.7928,lng:-4.8673},{n:"Ardrossan Town",c:"ADN",lat:55.6390,lng:-4.8150},{n:"Ardrossan Harbour",c:"ADS",lat:55.6380,lng:-4.8250},{n:"Irvine",c:"IRV",lat:55.6110,lng:-4.6750},{n:"Barassie",c:"BSS",lat:55.5600,lng:-4.6500},{n:"Troon",c:"TRN",lat:55.5450,lng:-4.6600},{n:"Prestwick Intl",c:"PRA",lat:55.5100,lng:-4.6000},{n:"Prestwick Town",c:"PTK",lat:55.4990,lng:-4.6150},{n:"Newton-on-Ayr",c:"NOA",lat:55.4700,lng:-4.6200},{n:"Ayr",c:"AYR",lat:55.4580,lng:-4.6250}], paths: [[[55.8580,-4.2580],[55.8460,-4.4280],[55.8320,-4.5050],[55.8230,-4.5200],[55.8100,-4.5600],[55.7890,-4.6220],[55.7280,-4.6850],[55.7060,-4.7200],[55.6560,-4.6980]],[[55.6560,-4.6980],[55.6360,-4.7550],[55.6335,-4.7845],[55.6428,-4.8058],[55.6953,-4.8555],[55.7600,-4.8560],[55.7928,-4.8673]],[[55.6428,-4.8058],[55.6390,-4.8150],[55.6380,-4.8250]],[[55.6560,-4.6980],[55.6110,-4.6750],[55.5600,-4.6500],[55.5450,-4.6600],[55.5100,-4.6000],[55.4580,-4.6250]]] },
                    northclyde: { color: '#00703c', pinClass: 'pin-nor', stations: [{n:"Helensburgh Central",c:"HLC",lat:56.0020,lng:-4.7290},{n:"Craigendoran",c:"CGD",lat:55.9950,lng:-4.7080},{n:"Cardross",c:"CDR",lat:55.9620,lng:-4.6600},{n:"Dalreoch",c:"DLR",lat:55.9450,lng:-4.5800},{n:"Dumbarton Central",c:"DBC",lat:55.9430,lng:-4.5680},{n:"Dumbarton East",c:"DBE",lat:55.9380,lng:-4.5500},{n:"Bowling",c:"BWG",lat:55.9280,lng:-4.4850},{n:"Kilpatrick",c:"KPT",lat:55.9220,lng:-4.4550},{n:"Dalmuir",c:"DMR",lat:55.9180,lng:-4.4250},{n:"Clydebank",c:"CYK",lat:55.9080,lng:-4.4050},{n:"Yoker",c:"YOK",lat:55.9000,lng:-4.3850},{n:"Garscadden",c:"GRS",lat:55.8950,lng:-4.3650},{n:"Scotstounhill",c:"SCH",lat:55.8850,lng:-4.3450},{n:"Hyndland",c:"HYN",lat:55.8780,lng:-4.3050},{n:"Partick",c:"PTK",lat:55.8700,lng:-4.3080},{n:"Charing Cross",c:"CHC",lat:55.8650,lng:-4.2700},{n:"Glasgow Queen St",c:"GLQ",lat:55.8620,lng:-4.2510}], paths: [[[56.0020,-4.7290],[55.9950,-4.7080],[55.9620,-4.6600],[55.9450,-4.5800],[55.9430,-4.5680]],[[55.9430,-4.5680],[55.9380,-4.5500],[55.9280,-4.4850],[55.9220,-4.4550],[55.9180,-4.4250],[55.9080,-4.4050],[55.9000,-4.3850],[55.8950,-4.3650],[55.8850,-4.3450],[55.8780,-4.3050],[55.8700,-4.3080],[55.8650,-4.2700],[55.8620,-4.2510]]] },
                    gourock: { color: '#28a197', pinClass: 'pin-gou', isBeta: true, stations: [{n:"Paisley Gilmour St",c:"PYG",lat:55.8460,lng:-4.4280},{n:"Bishopton",c:"BPT",lat:55.9060,lng:-4.5080},{n:"Langbank",c:"LGB",lat:55.9230,lng:-4.5800},{n:"Woodhall",c:"WDL",lat:55.9300,lng:-4.6550},{n:"Port Glasgow",c:"PTG",lat:55.9330,lng:-4.6850},{n:"Bogston",c:"BGS",lat:55.9350,lng:-4.7150},{n:"Cartsdyke",c:"CDY",lat:55.9400,lng:-4.7350},{n:"Greenock Central",c:"GKC",lat:55.9480,lng:-4.7550},{n:"Greenock West",c:"GKW",lat:55.9520,lng:-4.7650},{n:"Fort Matilda",c:"FTM",lat:55.9600,lng:-4.7850},{n:"Gourock",c:"GRK",lat:55.9630,lng:-4.8100}], paths: [[[55.8460,-4.4280],[55.9060,-4.5080],[55.9230,-4.5800],[55.9300,-4.6550],[55.9330,-4.6850],[55.9350,-4.7150],[55.9400,-4.7350],[55.9480,-4.7550],[55.9520,-4.7650],[55.9600,-4.7850],[55.9630,-4.8100]]] },
                    wemyssbay: { color: '#4c2c92', pinClass: 'pin-wem', isBeta: true, stations: [{n:"Port Glasgow",c:"PTG",lat:55.9330,lng:-4.6850},{n:"Whinhill",c:"WNL",lat:55.9390,lng:-4.7450},{n:"Drumfrochar",c:"DRF",lat:55.9395,lng:-4.7600},{n:"Branchton",c:"BCN",lat:55.9350,lng:-4.7850},{n:"Inverkip",c:"INP",lat:55.9050,lng:-4.8680},{n:"Wemyss Bay",c:"WMS",lat:55.8750,lng:-4.8880}], paths: [[[55.9330,-4.6850],[55.9390,-4.7450],[55.9395,-4.7600],[55.9350,-4.7850],[55.9050,-4.8680],[55.8750,-4.8880]]] },
                    ek: { color:
