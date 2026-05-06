```{r}
library(sf)
library(dplyr)
library(leaflet)
library(htmlwidgets)
library(jsonlite)

# ----------------------------
# SETTINGS
# ----------------------------
marker_png <- "marker_safe_png.png"  # relative to the rendered HTML output
marker_w <- 28
marker_h <- 28

pointsPerPart <- 160   # 80–220
partMs <- 1400         # ms to draw each part
pausePartMs <- 120     # ms pause between parts
pauseRouteMs <- 220    # ms pause between routes

# ----------------------------
# DATA
# routes_sf must exist (sf, EPSG:4326) with 'order' column
# ----------------------------
routes_sf <- routes_sf %>%
  mutate(order = as.integer(order)) %>%
  arrange(order)

# Convert sf -> GeoJSON text (temp file)
geojson_file <- tempfile(fileext = ".geojson")
sf::st_write(routes_sf, geojson_file, driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)
routes_geojson_txt <- paste(readLines(geojson_file, warn = FALSE), collapse = "\n")

# Parse GeoJSON into an R list so htmlwidgets can pass it to JS as an object (x.gj)
gj_list <- jsonlite::fromJSON(routes_geojson_txt, simplifyVector = FALSE)

# Leaflet widget
m <- leaflet(options = leafletOptions(zoomControl = TRUE)) %>%
  addProviderTiles("CartoDB.Positron")

js <- JS("
function(el, x) {
  var map = this;

  // Load RotatedMarker plugin (adds setRotationAngle)
  function loadScript(url, cb){
    var s = document.createElement('script');
    s.src = url;
    s.onload = cb;
    document.head.appendChild(s);
  }

  loadScript('https://unpkg.com/leaflet-rotatedmarker@0.2.0/leaflet.rotatedMarker.js', function(){

    var gj = x.gj;
    if (!gj || !gj.features || gj.features.length === 0) {
      console.warn('No GeoJSON features found.');
      return;
    }

    // Sort by order if present
    var feats = gj.features.slice().sort(function(a,b){
      var ao = a && a.properties ? +a.properties.order : NaN;
      var bo = b && b.properties ? +b.properties.order : NaN;
      if (Number.isNaN(ao) && Number.isNaN(bo)) return 0;
      if (Number.isNaN(ao)) return 1;
      if (Number.isNaN(bo)) return -1;
      return ao - bo;
    });

    // Fit bounds once
    try {
      var all = L.geoJSON(gj);
      map.fitBounds(all.getBounds(), { padding: [20, 20] });
    } catch(e) {}

    // Controls from R
    var pointsPerPart = x.pointsPerPart;
    var partMs = x.partMs;
    var pausePartMs = x.pausePartMs;
    var pauseRouteMs = x.pauseRouteMs;

    // Gradient endpoints: #0075A9E6 -> #53284F
    var start = { r: 0x00, g: 0x75, b: 0xA9, a: 0xE6/255.0 };
    var end   = { r: 0x53, g: 0x28, b: 0x4F, a: 1.0 };
    function lerp(a,b,t){ return a + (b-a)*t; }
    function rgba(c){
      return 'rgba(' + Math.round(c.r) + ',' + Math.round(c.g) + ',' + Math.round(c.b) + ',' + c.a.toFixed(3) + ')';
    }
    function colorAt(t){
      t = Math.max(0, Math.min(1, t));
      return rgba({
        r: lerp(start.r, end.r, t),
        g: lerp(start.g, end.g, t),
        b: lerp(start.b, end.b, t),
        a: lerp(start.a, end.a, t)
      });
    }

    // Bearing for rotation
    function bearingDeg(lat1, lng1, lat2, lng2) {
      var toRad = Math.PI / 180, toDeg = 180 / Math.PI;
      var p1 = lat1 * toRad, p2 = lat2 * toRad;
      var dl = (lng2 - lng1) * toRad;
      var y = Math.sin(dl) * Math.cos(p2);
      var z = Math.cos(p1)*Math.sin(p2) - Math.sin(p1)*Math.cos(p2)*Math.cos(dl);
      var t = Math.atan2(y, z) * toDeg;
      return (t + 360) % 360;
    }

    // Group that accumulates drawn segments
    var group = L.layerGroup().addTo(map);

    // Tracer marker
    var markerIcon = L.icon({
      iconUrl: x.markerUrl,
      iconSize: [x.markerW, x.markerH],
      iconAnchor: [Math.round(x.markerW/2), x.markerH]
    });

    var tracer = null;

    // Densify into N points
    function densify(coords, n) {
      var segLens = [], total = 0;
      for (var i=0; i<coords.length-1; i++) {
        var a = coords[i], b = coords[i+1];
        var dx = b[0]-a[0], dy = b[1]-a[1];
        var len = Math.sqrt(dx*dx + dy*dy);
        segLens.push(len); total += len;
      }
      if (total === 0) return coords;

      var out = [];
      for (var k=0; k<n; k++) {
        var d = (k/(n-1)) * total;
        var acc = 0;
        for (var s=0; s<segLens.length; s++) {
          var Ls = segLens[s];
          if (acc + Ls >= d || s === segLens.length-1) {
            var a = coords[s], b = coords[s+1];
            var local = (Ls === 0) ? 0 : (d - acc)/Ls;
            out.push([ a[0] + local*(b[0]-a[0]), a[1] + local*(b[1]-a[1]) ]);
            break;
          }
          acc += Ls;
        }
      }
      return out;
    }

    // Keep MultiLineString parts separate (prevents jump connectors)
    function getParts(feature) {
      var g = feature.geometry;
      if (!g) return [];
      if (g.type === 'LineString') return [g.coordinates];
      if (g.type === 'MultiLineString') return g.coordinates;
      return [];
    }

    function drawPartSlow(coords, done) {
      if (!coords || coords.length < 2) { done(); return; }

      var pts = densify(coords, pointsPerPart);

      if (!tracer) {
        tracer = L.marker([pts[0][1], pts[0][0]], {
          icon: markerIcon,
          rotationAngle: 0,
          rotationOrigin: 'center center'
        }).addTo(map);
      } else {
        tracer.setLatLng([pts[0][1], pts[0][0]]);
      }

      var idx = 1;
      var stepMs = Math.max(10, Math.floor(partMs / pointsPerPart));

      var timer = setInterval(function() {
        if (idx >= pts.length) {
          clearInterval(timer);
          setTimeout(done, pausePartMs);
          return;
        }

        var a = pts[idx-1], b = pts[idx];
        var t = idx / (pts.length - 1);
        var segColor = colorAt(t);

        L.polyline([[a[1], a[0]], [b[1], b[0]]], {
          color: segColor,
          weight: 5,
          opacity: 1
        }).addTo(group);

        tracer.setLatLng([b[1], b[0]]);
        var ang = bearingDeg(a[1], a[0], b[1], b[0]);
        if (tracer.setRotationAngle) tracer.setRotationAngle(ang);

        idx++;
      }, stepMs);
    }

    function drawRouteSlow(feature, done) {
      var parts = getParts(feature);
      var p = 0;
      function nextPart() {
        if (p >= parts.length) { setTimeout(done, pauseRouteMs); return; }
        drawPartSlow(parts[p], function(){ p++; nextPart(); });
      }
      nextPart();
    }

    var i = 0;
    function nextRoute() {
      if (i >= feats.length) return;
      drawRouteSlow(feats[i], function(){ i++; nextRoute(); });
    }

    nextRoute();
  });
}
")

m <- onRender(
  m,
  js,
  data = list(
    gj = gj_list,
    markerUrl = gsub("\\\\", "/", marker_png),
    markerW = marker_w,
    markerH = marker_h,
    pointsPerPart = pointsPerPart,
    partMs = partMs,
    pausePartMs = pausePartMs,
    pauseRouteMs = pauseRouteMs
  )
)

m