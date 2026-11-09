(function () {
  if (window.__zigeDownloadBridge) return;
  window.__zigeDownloadBridge = true;

  // La pagina esporta JSON e CSV creando un Blob e cliccando un link
  // `download`. In WKWebView i blob non sempre aprono NSSavePanel:
  // li intercettiamo e passiamo i byte all'app nativa.
  document.addEventListener("click", function (event) {
    var link = event.target && event.target.closest
      ? event.target.closest("a[download]")
      : null;
    if (!link || !link.href || link.href.indexOf("blob:") !== 0) return;

    event.preventDefault();
    event.stopImmediatePropagation();

    var name = link.download || "download";
    fetch(link.href)
      .then(function (response) { return response.blob(); })
      .then(function (blob) {
        var reader = new FileReader();
        reader.onloadend = function () {
          var result = String(reader.result || "");
          var comma = result.indexOf(",");
          window.webkit.messageHandlers.zigeSaveFile.postMessage({
            name: name,
            mime: blob.type || "application/octet-stream",
            base64: comma >= 0 ? result.slice(comma + 1) : ""
          });
        };
        reader.readAsDataURL(blob);
      })
      .catch(function (error) {
        console.error("Zige download bridge:", error);
      });
  }, true);
})();
