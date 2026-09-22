QBScoreboard = {};

$(document).ready(function () {
	window.addEventListener("message", function (event) {
		switch (event.data.action) {
			case "open":
				QBScoreboard.Open(event.data);
				break;
			case "close":
				QBScoreboard.Close();
				break;
		}
	});
});

QBScoreboard.Open = function (data) {
	$(".scoreboard-block").fadeIn(150);

	$("#total-players").html("<p>" + data.players + " SUR " + data.maxPlayers + "</p>");

	// var panel1 = data.players + 2
	// var panel2 = data.players + 1
	// var panel3 = data.players
	// var panel4 = data.players + 3
	// var panel5 = data.players + 2

	// // var image1 = "fortnite-icon-two.png"

	//     $("#total-players1").html("<img style=' width: 30px; height: 30px; background-color: red; ' src='fortnite-icon-two-"+panel1+".png'  />"); // 1
	//     $("#total-players2").html("<img style=' width: 30px; height: 30px; background-color: green; ' src='fortnite-icon-two-"+panel2+".png'  />"); // 2
	//     $("#total-players3").html("<img style=' width: 30px; height: 30px; background-color: gray; ' src='fortnite-icon-two-"+panel3+".png'  />"); // main
	//     $("#total-players4").html("<img style=' width: 30px; height: 30px; background-color: black; ' src='fortnite-icon-two-"+panel4+".png'  />"); // 3
	//     $("#total-players5").html("<img style=' width: 30px; height: 30px; background-color: white; ' src='fortnite-icon-two-"+panel5+".png'  />"); // 4

	// } else {

	//     $("#total-players").html("<img style=' width: 30px; height: 30px;   margin-top: 5px;  margin-left: -20px;  position: absolute !important;  ' src='fortnite-icon-two.png'  />");

	// }

	$("#bateal-pass").html("<p>" + data.ogtal3b + "</p>");

	$.each(data.requiredCops, function (i, category) {
		var beam = $(".scoreboard-info").find('[data-type="' + i + '"]');
		var status = $(beam).find(".info-beam-status");

		if (category.busy) {
			$(status).html('<i class="fas fa-clock"></i>');
		} else if (data.currentCops >= category.minimum) {
			$(status).html('<i class="fas fa-circle"></i>');
		} else {
			$(status).html('<i class="fas fa-exclamation-circle"></i>');
		}

		if (data.currentCops > 0) {
			var Abeam = $(".scoreboard-info").find('[data-type="police"]');
			var Astatus = $(Abeam).find(".info-beam-status");
			$(Astatus).html('<i class="fas fa-circle"></i>');
		} else {
			var Abeam = $(".scoreboard-info").find('[data-type="police"]');
			var Astatus = $(Abeam).find(".info-beam-status");
			$(Astatus).html('<i class="fas fa-exclamation-circle"></i>');
		}

		if (data.currentAmbulance > 0) {
			var Abeam = $(".scoreboard-info").find('[data-type="ambulance"]');
			var Astatus = $(Abeam).find(".info-beam-status");
			$(Astatus).html('<i class="fas fa-circle"></i>');
		} else {
			var Abeam = $(".scoreboard-info").find('[data-type="ambulance"]');
			var Astatus = $(Abeam).find(".info-beam-status");
			$(Astatus).html('<i class="fas fa-exclamation-circle"></i>');
		}
	});
};

QBScoreboard.Close = function () {
	$(".scoreboard-block").fadeOut(150);
};
