#ifndef __MESSAGE_H
#define __MESSAGE_H

enum
{
	MESSAGE = 243,
};

typedef nx_struct demo_message
{
	nx_uint16_t lastReading;
	nx_bool axis;
} demo_message_t;

#endif __MESSAGE_H

