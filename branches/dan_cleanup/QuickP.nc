#include <math.h>
#include "Accel.h"
#include "printf.h"

module QuickP {
	uses interface Boot;

	uses interface AMSend;
	uses interface Receive;
	uses interface Packet;
	uses interface SplitControl as RadioControl;

	uses interface Timer<TMilli> as AccelTimer;
	uses interface Timer<TMilli> as StartTimer;
	uses interface Timer<TMilli> as CountDownTimer;
	uses interface Timer<TMilli> as FireTimer;
	uses interface Timer<TMilli> as DrawTimer;

	uses interface Read<uint16_t> as ReadX;
	uses interface Read<uint16_t> as ReadY;

	uses interface Leds;
	uses interface Mts300Sounder;
}
implementation {
	enum {
		NODE0_X_POS_1G = 547,
		NODE0_X_NEG_1G = 436,
		NODE0_Y_POS_1G = 580,
		NODE0_Y_NEG_1G = 474,

		NODE1_X_POS_1G = 551,
		NODE1_X_NEG_1G = 440,
		NODE1_Y_POS_1G = 573,
		NODE1_Y_NEG_1G = 462,

		TIMER_PERIOD = 21
	};

	accel_t accelValues;
	message_t bufx, bufy, bufd;
	uint8_t countDown = 0;
	uint16_t draw_time = 0;
	bool startDone = FALSE;
	bool fireDone = FALSE;
	bool checkFire = FALSE;
	bool busy = FALSE;

	task void processXValues();
	task void processYValues();
	task void ReportTime();
	task void sendDrawTime();
	uint16_t convertX(uint16_t data);
	uint16_t convertY(uint16_t data);
	void printfFloat(float toBePrinter);

	event void Boot.booted() {
		call RadioControl.start();
		printf ("My ID is %d\n", TOS_NODE_ID);
		printfflush();
	}

	event void RadioControl.startDone(error_t err) {
		call AccelTimer.startPeriodic(TIMER_PERIOD);
	}

	task void ReadSensors() {
		if (call ReadX.read() != SUCCESS)
			post ReadSensors();
		
		if (call ReadY.read() != SUCCESS)
			post ReadSensors();
	}

	event void AccelTimer.fired() {
		post ReadSensors();
	}

	event void StartTimer.fired() {
		startDone = TRUE;
		call Mts300Sounder.beep(100);
		call CountDownTimer.startPeriodic(1024);
		call Leds.led1On();
	}

	event void CountDownTimer.fired() {
		if ( ++countDown >= 3 ) {
			call Mts300Sounder.beep(500);
			call CountDownTimer.stop();
			call DrawTimer.startPeriodic(1);
			call Leds.led2On();
			checkFire = TRUE;
		} else
			call Mts300Sounder.beep(100);
	}

	event void FireTimer.fired() {
		call Mts300Sounder.beep(1000);
		call DrawTimer.stop();
		call Leds.led0On();
		checkFire = FALSE;
		startDone = FALSE;
		fireDone = TRUE;
		post ReportTime();
	}

	event void DrawTimer.fired() {
		draw_time ++;
	}

	event void ReadX.readDone(error_t result, uint16_t val) {
		//call Leds.led0Toggle();
		if (result != SUCCESS) {
			post ReadSensors();
			return;
		}

		accelValues.x = val;
		//printf ("X == %i\n", val);
		//printfflush();
		post processXValues();
	}

	event void ReadY.readDone(error_t result, uint16_t val) {
		//call Leds.led1Toggle();
		if (result != SUCCESS) {
			post ReadSensors();
			return;
		}

		accelValues.y = val;
		//printf ("Y == %i\n", val);
		//printfflush();
		post processYValues();
	}

	task void ReportTime() {
		demo_message_t *payload;
		payload = (demo_message_t *)call Packet.getPayload(&bufd, sizeof(demo_message_t));
		payload->lastReading = draw_time;
		payload->axis = TOS_NODE_ID;
		draw_time = 0;
		post sendDrawTime();
	}

	task void sendDrawTime() {
		if (call AMSend.send(2, &bufd, sizeof(demo_message_t)) != SUCCESS)
			post sendDrawTime();
	}

	task void sendMessageX() {
		//AM_BROADCAST_ADDR
		if (call AMSend.send(1, &bufx, sizeof(demo_message_t)) != SUCCESS)
			post sendMessageX();
	}

	task void sendMessageY() {
		if (call AMSend.send(1, &bufy, sizeof(demo_message_t)) != SUCCESS)
			post sendMessageY();
	}

	task void processXValues() {
		uint16_t x_angle;
		/*demo_message_t *payload;

		payload = (demo_message_t *)call Packet.getPayload(&bufx, sizeof(demo_message_t));
		*/
		x_angle = convertX(accelValues.x);
		if (x_angle == (uint16_t)NULL)
			return;

		/*payload->lastReading = x_angle;

		payload->axis = TRUE;

		post sendMessageX();
		*/
	}

	task void processYValues() {
		uint16_t y_angle;
		/*demo_message_t *payload;

		payload = (demo_message_t *)call Packet.getPayload(&bufy, sizeof(demo_message_t));
		*/
		y_angle = convertY(accelValues.y);
		
		if (y_angle == (uint16_t)NULL)
			return;

		/*payload->lastReading = y_angle;
		payload->axis = FALSE;
		post sendMessageY();
		*/

		if (y_angle >= 65 && y_angle <= 90) {
			if ( ! call StartTimer.isRunning() && !startDone )
				call StartTimer.startOneShot(1024);
		} else if ((checkFire || fireDone) && y_angle >=0 && y_angle <= 15) {
			if (!call FireTimer.isRunning() && !fireDone)
				call FireTimer.startOneShot(512);
		} else if (!checkFire && !fireDone) {
			call Leds.led0Off();
			call Leds.led1Off();
			call Leds.led2Off();
			call StartTimer.stop();
			call FireTimer.stop();
			call CountDownTimer.stop();
			startDone = FALSE;
			fireDone = FALSE;
			countDown = 0;
		} else if (!checkFire) {
			call StartTimer.stop();
			call FireTimer.stop();
			call CountDownTimer.stop();
			startDone = FALSE;
			fireDone = FALSE;
			countDown = 0;
		}
	}

	event void AMSend.sendDone(message_t *msg, error_t err) {
		if(err != SUCCESS) {
			post sendMessageX();
			post sendMessageY();
		} //else
			//call Leds.led2Toggle();
	}

	event message_t * Receive.receive(message_t *msg, void *payload, uint8_t len) { 
		demo_message_t *demo_payload = (demo_message_t *)payload;
		
		call Leds.led2Toggle();

		//printf("Received: %c == %i\n", (demo_payload->axis)? 'X':'Y', demo_payload->lastReading);
		printf("%s's Draw Time = %i ms\n", (demo_payload->axis)? "Dan": "Cronin", demo_payload->lastReading);
		printfflush();

		return msg;
	}

	event void RadioControl.stopDone(error_t err) {}

	uint16_t convertX(uint16_t data) {
		float scale_factor, reading;
		int16_t accel_data = data;
		int16_t x_neg_1g = (TOS_NODE_ID)? NODE1_X_NEG_1G : NODE0_X_NEG_1G;
		int16_t x_pos_1g = (TOS_NODE_ID)? NODE1_X_POS_1G : NODE0_X_POS_1G;
		bool local_busy = FALSE;

		atomic {
			local_busy = busy;
			busy = TRUE;
		}

		if (local_busy) {
			printf ("!!!SKIPPING VALUES!!!!\n" );
			return (uint16_t)NULL;
		}

		scale_factor = ((float)(x_pos_1g - x_neg_1g) / 2.0);

		// If (x_pos_1g - accel_data) is a negative number, then reading > 1.0
		// then asin() returns an error.
		reading = 1.0 - fabs((float)(x_pos_1g - accel_data) / scale_factor);

		if ( reading < -1.0 || reading > 1.0) {
			busy = FALSE;
			return (uint16_t)NULL;
		}

		reading = asin(reading) * (180.0 / M_PI);// 57.29577951; // (180 / M_PI) = Degrees

		busy = FALSE;
		return (uint16_t)fabs(reading);
	}

	uint16_t convertY(uint16_t data) {
		float scale_factor, reading;
		int16_t accel_data = data;
		int16_t y_neg_1g = (TOS_NODE_ID)? NODE1_Y_NEG_1G : NODE0_Y_NEG_1G;
		int16_t y_pos_1g = (TOS_NODE_ID)? NODE1_Y_POS_1G : NODE0_Y_POS_1G;
		bool local_busy = FALSE;

		atomic {
			local_busy = busy;
			busy = TRUE;
		}

		if (local_busy) {
			printf ("!!!SKIPPING VALUES!!!!\n" );
			return (uint16_t)NULL;
		}

		scale_factor = ((float)(y_pos_1g - y_neg_1g) / 2.0);

		reading = 1.0 - fabs((float)(y_pos_1g - accel_data) / scale_factor);

		if ( reading < -1.0 || reading > 1.0) {
			busy = FALSE;
			return (uint16_t)NULL;
		}

		reading = asin(reading) * (180.0 / M_PI);//57.29577951;

		busy = FALSE;
		return (uint16_t)fabs(reading);
	}

	void printfFloat(float toBePrinted) {
		uint32_t fi, f0, f1, f2;
		char c;
		float f = toBePrinted;

		if (f<0){
			c = '-'; f = -f;
		} else {
			c = ' ';
		}

		// integer portion.
		fi = (uint32_t) f;

		// decimal portion...get index for up to 3 decimal places.
		f = f - ((float) fi);
		f0 = f*10;   f0 %= 10;
		f1 = f*100;  f1 %= 10;
		f2 = f*1000; f2 %= 10;
		printf("%c%ld.%d%d%d\n", c, fi, (uint8_t) f0, (uint8_t) f1, (uint8_t) f2);
	}

}
