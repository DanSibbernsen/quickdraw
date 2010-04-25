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
	uses interface Timer<TMilli> as ACKTimer;

	uses interface Read<uint16_t> as ReadX;
	uses interface Read<uint16_t> as ReadY;

	uses interface Leds;
	uses interface Mts300Sounder;
}
implementation {
	accel_t accelValues;
	message_t bufx, bufy, bufd, buf_ref, buf_ack;
	uint8_t countDown = 0;
	uint16_t draw_time = 0;
	bool startDone = FALSE;
	bool fireDone = FALSE;
	bool checkFire = FALSE;
	bool busy = FALSE;
	bool readyReceived = FALSE;
	uint8_t numberOfACKsReceived = 0;
	int8_t ack_node_id_0;
	int8_t ack_node_id_1;
	uint16_t Node0FireTime = 0;
	uint16_t Node1FireTime = 0;

	task void processXValues();
	task void processYValues();
	task void ReportTime();
	task void sendDrawTime();
	task void sendMessageY();
	task void sendACK();
	uint16_t convertX(uint16_t data);
	uint16_t convertY(uint16_t data);
	void printfFloat(float toBePrinter);
	void reset();
	void resetAll();

	event void Boot.booted() {
		call RadioControl.start();
		printf ("My ID is %d\n", TOS_NODE_ID);
		printfflush();
	}

	event void RadioControl.startDone(error_t err) {
		call AccelTimer.startPeriodic(TIMER_PERIOD);
	}

	task void ReadSensors() {
		//if (call ReadX.read() != SUCCESS)
			//post ReadSensors();
		
		if (call ReadY.read() != SUCCESS)
			post ReadSensors();
	}

	event void AccelTimer.fired() {
		post ReadSensors();
	}


	event void StartTimer.fired() {
		quick_message *payload;

		payload = (quick_message *)call Packet.getPayload(&bufy, sizeof(quick_message));
		payload->id = TOS_NODE_ID;
		payload->messageType = READY;
		post sendMessageY();

		startDone = TRUE;
		call Mts300Sounder.beep(100);
		//call CountDownTimer.startPeriodic(1024);
		//call Leds.led1On();
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
		quick_message *payload;
		payload = (quick_message *)call Packet.getPayload(&bufd, sizeof(quick_message));
		payload->time = draw_time;
		payload->id = TOS_NODE_ID;
		payload->messageType = FIRE;
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
		if (call AMSend.send(2, &bufy, sizeof(quick_message)) != SUCCESS)
			post sendMessageY();
	}

	task void sendACK()
	{
		if (call AMSend.send(2, &buf_ack, sizeof(quick_message)) != SUCCESS)
			post sendACK();
	}

	task void sendMessageAll() {
		if (call AMSend.send(AM_BROADCAST_ADDR, &bufx, sizeof(quick_message)) != SUCCESS)
			post sendMessageAll();
	}


	event void ACKTimer.fired() {
		quick_message *payload;

		if(numberOfACKsReceived < 2)
		{

			payload = (quick_message *)call Packet.getPayload(&bufx, sizeof(quick_message));
			payload->id = TOS_NODE_ID;
			payload->messageType = STOP;
			post sendMessageAll();
			readyReceived = FALSE;
			if(ack_node_id_1 == -1)
			{
				printf ("Did NOT receive ACK from %s, resetting...\n", "Dan");
			}
			if (ack_node_id_0 == -1)
			{
				printf ("Did NOT receive ACK from %s, resetting...\n", "Cronin");
			}
			printfflush();
		}
		
	}

	task void sendMessageRef() {
		if (call AMSend.send(AM_BROADCAST_ADDR, &buf_ref, sizeof(quick_message)) != SUCCESS)
			post sendMessageRef();
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
		
		y_angle = convertY(accelValues.y);
		
		if (y_angle == (uint16_t)NULL)
			return;

		if (y_angle >= 65 && y_angle <= 90) {
			if ( ! call StartTimer.isRunning() && !startDone )
				call StartTimer.startOneShot(1024);
		} else if ((checkFire || fireDone) && y_angle >=0 && y_angle <= 15) {
			if (!call FireTimer.isRunning() && !fireDone)
				call FireTimer.startOneShot(512);
		} else if (!checkFire && !fireDone) {
			quick_message *payload;
			if (startDone) {
				payload = (quick_message *)call Packet.getPayload(&bufx, sizeof(quick_message));
				payload->id = TOS_NODE_ID;
				payload->messageType = STOP;
				post sendMessageAll();
			}
			resetAll();
		} else if (!checkFire) {
			reset();
		}
	}

	event void AMSend.sendDone(message_t *msg, error_t err) {
		if(err != SUCCESS) {
			//post sendMessageX();
			post sendMessageY();
		} //else
			//call Leds.led2Toggle();
	}

	void reset() {
		call StartTimer.stop();
		call FireTimer.stop();
		call CountDownTimer.stop();
		call DrawTimer.stop();
		startDone = FALSE;
		fireDone = FALSE;
		countDown = 0;
	}

	void resetAll() {
		call Leds.led0Off();
		call Leds.led1Off();
		call Leds.led2Off();
		reset();
	}

	event message_t * Receive.receive(message_t *msg, void *payload, uint8_t len) { 
		quick_message *payload_out;
		quick_message *payload_in = (quick_message *)payload;
		
		payload_out = (quick_message *)call Packet.getPayload(&buf_ref, sizeof(quick_message));

		call Leds.led2Toggle();

		if (TOS_NODE_ID < 2) {
			if (payload_in->messageType == START) {
				payload_out = (quick_message *)call Packet.getPayload(&buf_ack, sizeof(quick_message));
				payload_out->id = TOS_NODE_ID;
				payload_out->messageType = ACK;
				post sendACK();
				call CountDownTimer.startPeriodic(1024);
				call Leds.led1On();
			} else if (payload_in->messageType == STOP) {
				resetAll();
			}
		} else {
			if (payload_in->messageType == READY) {
				printf ("Received Ready from %s(%i)\n", (payload_in->id)? "Cronin": "Dan", payload_in->id);
				printfflush();

				if (readyReceived) {
					ack_node_id_0 = -1;
					ack_node_id_1 = -1;
					Node0FireTime = 0;
					Node1FireTime = 0;
					payload_out->id = TOS_NODE_ID;
					payload_out->messageType = START;
					numberOfACKsReceived = 0;
					call ACKTimer.startPeriodic(1536); // 1.5 secs to make sure both motes ACK the START packet
					post sendMessageRef();
					readyReceived = FALSE;
				} else
					readyReceived = TRUE;
			} else if (payload_in->messageType == FIRE) {
				if(payload_in->id == 0)
				{
					Node0FireTime = payload_in->time;
				}
				else if(payload_in->id == 1)
				{
					Node1FireTime = payload_in->time;
				}
				printf("%s's Draw Time = %i ms\n", (payload_in->id)? "Cronin": "Dan", payload_in->time);
				if(Node1FireTime != 0 && Node0FireTime != 0)
				{
					if(Node0FireTime < Node1FireTime)
					{
						printf("Dan (node 0) wins!\n");
					}
					else
					{
						printf("Cronin (node 1) wins!\n");
					}

				}
				printfflush();
			} else if (payload_in->messageType ==  STOP) {
				printf("%s(%i) messed up, starting over!\n", (payload_in->id)? "Cronin": "Dan", payload_in->id);
				printfflush();
				readyReceived = FALSE;
			}
			else if (payload_in->messageType == ACK) {
				printf("%s(%i) has sent an ACK\n", (payload_in->id)? "Cronin": "Dan", payload_in->id);
				printfflush();
				++numberOfACKsReceived;
				if(payload_in->id)
				{
					ack_node_id_1 = 1;
				}
				else
				{
					ack_node_id_0 = 1;
				}
			}
		}

		//printf("Received: %c == %i\n", (demo_payload->axis)? 'X':'Y', demo_payload->lastReading);
		//printf("%s's Draw Time = %i ms\n", (demo_payload->axis)? "Dan": "Cronin", demo_payload->lastReading);
		//printfflush();

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
